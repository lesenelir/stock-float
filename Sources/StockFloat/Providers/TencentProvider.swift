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
            continuation.yield(.offline(.unreachable))
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

  /// Parse `v_usAAPL="200~苹果~AAPL.OQ~333.27~330.32~…";` statements; fields are 1 name, 3 price, 4 previous
  /// close, 30 quote time.
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
      return Quote(
        symbol: symbol.id, name: String(fields[1]), price: price, prevClose: prevClose,
        time: fields.count > 30 ? time(String(fields[30]), in: symbol.market) : nil)
    }
  }

  /// Read a quote time, which is local to the market and punctuated differently in each:
  /// `2026-10-02 13:30:40`, `2026/10/02 16:08:10`, `20260930161458`.
  static func time(_ text: String, in market: Market) -> Date? {
    let digits = text.filter(\.isNumber).compactMap(\.wholeNumberValue)
    guard digits.count == 14 else { return nil }
    func number(_ range: Range<Int>) -> Int {
      digits[range].reduce(0) { $0 * 10 + $1 }
    }
    var calendar = Calendar(identifier: .gregorian)
    switch market {
    case .us: calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    case .hk: calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .gmt
    case .sh, .sz: calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
    }
    return calendar.date(
      from: DateComponents(
        year: number(0..<4), month: number(4..<6), day: number(6..<8),
        hour: number(8..<10), minute: number(10..<12), second: number(12..<14)))
  }

  private static let quoteTrim = CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines)

  private static let gb18030 = String.Encoding(
    rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
  )
}
