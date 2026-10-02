import Foundation

/// Polls Tencent's public quote endpoint. Unofficial; US quotes arrive as snapshots roughly every 20 seconds.
struct TencentProvider: QuoteProvider {
  var pollSeconds: Double = 3
  var session: URLSession = .shared

  func events(for symbols: [StockSymbol]) -> AsyncStream<QuoteEvent> {
    AsyncStream { continuation in
      let task = Task {
        while !Task.isCancelled {
          do {
            let quotes = try await fetch(symbols)
            continuation.yield(.online)
            for quote in quotes {
              continuation.yield(.quote(quote))
            }
          } catch {
            continuation.yield(.offline(hint: nil))
          }
          try? await Task.sleep(for: .seconds(pollSeconds))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func fetch(_ symbols: [StockSymbol]) async throws -> [Quote] {
    guard let url = Self.url(for: symbols) else { throw URLError(.badURL) }
    let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    guard let text = String(data: data, encoding: Self.gb18030) else {
      throw URLError(.cannotDecodeContentData)
    }
    return Self.parse(text)
  }

  static func url(for symbols: [StockSymbol]) -> URL? {
    URL(string: "https://qt.gtimg.cn/q=" + symbols.map(requestKey).joined(separator: ","))
  }

  // Plain `hk` codes are delayed; the `r_` prefix asks for the real-time feed.
  static func requestKey(_ symbol: StockSymbol) -> String {
    symbol.market == .hk ? "r_" + symbol.id : symbol.id
  }

  /// Parse `v_usAAPL="200~苹果~AAPL.OQ~333.27~330.32~…";` statements; fields are 1 name, 3 price, 4 previous close.
  static func parse(_ text: String) -> [Quote] {
    text.split(separator: ";").compactMap { statement in
      guard let equals = statement.firstIndex(of: "=") else { return nil }
      var key = statement[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
      guard key.hasPrefix("v_") else { return nil }
      key.removeFirst(2)
      if key.hasPrefix("r_") {
        key.removeFirst(2)
      }
      guard let symbol = StockSymbol(id: key) else { return nil }

      let body = statement[statement.index(after: equals)...].trimmingCharacters(in: quoteTrim)
      let fields = body.split(separator: "~", omittingEmptySubsequences: false)
      guard fields.count > 4,
        let price = Double(fields[3]),
        let prevClose = Double(fields[4]),
        price > 0
      else { return nil }
      return Quote(symbol: symbol.id, name: String(fields[1]), price: price, prevClose: prevClose)
    }
  }

  private static let quoteTrim = CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines)

  private static let gb18030 = String.Encoding(
    rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
  )
}
