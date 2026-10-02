import Foundation
import os

/// Streams US trades from Finnhub's WebSocket; the previous close comes from its REST quote endpoint.
struct FinnhubProvider: QuoteProvider {
  let apiKey: String
  var session: URLSession = .shared

  private static let referenceInterval: Double = 300
  private static let pingInterval: Double = 15

  func events(for symbols: [StockSymbol]) -> AsyncStream<QuoteEvent> {
    AsyncStream { continuation in
      let task = Task {
        let book = FinnhubBook()
        await withTaskGroup(of: Void.self) { group in
          group.addTask { await pollReference(symbols, book, continuation) }
          group.addTask { await streamTrades(symbols, book, continuation) }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: Previous close

  private func pollReference(
    _ symbols: [StockSymbol],
    _ book: FinnhubBook,
    _ continuation: AsyncStream<QuoteEvent>.Continuation
  ) async {
    while !Task.isCancelled {
      var failed = false
      for symbol in symbols {
        do {
          let reference = try await fetchReference(symbol.code)
          let quote = await book.reference(
            ticker: symbol.code, price: reference.c, prevClose: reference.pc, time: reference.t)
          if let quote {
            continuation.yield(.quote(quote))
          }
        } catch {
          failed = true
        }
      }
      try? await Task.sleep(for: .seconds(failed ? 15 : Self.referenceInterval))
    }
  }

  private func fetchReference(_ ticker: String) async throws -> FinnhubReference {
    guard var components = URLComponents(string: "https://finnhub.io/api/v1/quote") else {
      throw URLError(.badURL)
    }
    components.queryItems = [
      URLQueryItem(name: "symbol", value: ticker),
      URLQueryItem(name: "token", value: apiKey),
    ]
    guard let url = components.url else { throw URLError(.badURL) }
    let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(FinnhubReference.self, from: data)
  }

  // MARK: Trades

  private func streamTrades(
    _ symbols: [StockSymbol],
    _ book: FinnhubBook,
    _ continuation: AsyncStream<QuoteEvent>.Continuation
  ) async {
    var backoff = 1.0
    while !Task.isCancelled {
      let established = await connect(symbols, book, continuation)
      continuation.yield(.offline(.unreachable))
      backoff = established ? 1 : min(backoff * 2, 60)
      try? await Task.sleep(for: .seconds(backoff))
    }
  }

  /// Run one socket until it fails; returns whether the subscription was ever established.
  private func connect(
    _ symbols: [StockSymbol],
    _ book: FinnhubBook,
    _ continuation: AsyncStream<QuoteEvent>.Continuation
  ) async -> Bool {
    guard var components = URLComponents(string: "wss://ws.finnhub.io") else { return false }
    components.queryItems = [URLQueryItem(name: "token", value: apiKey)]
    guard let url = components.url else { return false }

    let socket = session.webSocketTask(with: url)
    socket.resume()
    let established = OSAllocatedUnfairLock(initialState: false)
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await keepAlive(socket) }
      group.addTask {
        do {
          for symbol in symbols {
            try await socket.send(.string(#"{"type":"subscribe","symbol":"\#(symbol.code)"}"#))
          }
          established.withLock { $0 = true }
          continuation.yield(.online)
          while !Task.isCancelled {
            guard let data = try await Self.payload(of: socket.receive()) else { continue }
            for trade in Self.latestTrades(in: data) {
              let quote = await book.trade(ticker: trade.s, price: trade.p, time: trade.t / 1000)
              if let quote {
                continuation.yield(.quote(quote))
              }
            }
          }
        } catch {}
      }
      // `receive()` ignores task cancellation, so closing the socket is what unblocks the other child.
      await group.next()
      group.cancelAll()
      socket.cancel(with: .goingAway, reason: nil)
    }
    return established.withLock { $0 }
  }

  /// Close the socket when a ping goes unanswered, which a half-open connection would otherwise hide.
  private func keepAlive(_ socket: URLSessionWebSocketTask) async {
    let awaitingPong = OSAllocatedUnfairLock(initialState: false)
    while true {
      do {
        try await Task.sleep(for: .seconds(Self.pingInterval))
      } catch {
        return
      }
      if awaitingPong.withLock({ $0 }) {
        return
      }
      awaitingPong.withLock { $0 = true }
      socket.sendPing { error in
        if error == nil {
          awaitingPong.withLock { $0 = false }
        }
      }
    }
  }

  private static func payload(of message: URLSessionWebSocketTask.Message) -> Data? {
    switch message {
    case .string(let text): Data(text.utf8)
    case .data(let data): data
    @unknown default: nil
    }
  }

  /// The most recent trade per ticker in one WebSocket frame; non-trade frames (pings, errors) yield nothing.
  static func latestTrades(in data: Data) -> [FinnhubTrade] {
    guard let message = try? JSONDecoder().decode(FinnhubMessage.self, from: data), message.type == "trade" else {
      return []
    }
    var latest: [String: FinnhubTrade] = [:]
    for trade in message.data ?? [] where trade.t >= latest[trade.s]?.t ?? 0 {
      latest[trade.s] = trade
    }
    return latest.values.sorted { $0.s < $1.s }
  }
}

struct FinnhubTrade: Decodable, Equatable {
  /// Ticker.
  let s: String
  /// Price.
  let p: Double
  /// Trade time, milliseconds since the epoch.
  let t: Double
}

private struct FinnhubMessage: Decodable {
  let type: String
  let data: [FinnhubTrade]?
}

private struct FinnhubReference: Decodable {
  /// Current price.
  let c: Double
  /// Previous close.
  let pc: Double
  /// Time of `c`, seconds since the epoch.
  let t: Double
}

/// Merges REST snapshots and WebSocket trades into quotes, keeping whichever price is newer.
actor FinnhubBook {
  private struct Entry {
    var price = 0.0
    var priceTime = 0.0
    var prevClose = 0.0
  }

  private var entries: [String: Entry] = [:]

  /// Record a REST snapshot. Times are seconds since the epoch.
  func reference(ticker: String, price: Double, prevClose: Double, time: Double) -> Quote? {
    var entry = entries[ticker] ?? Entry()
    entry.prevClose = prevClose
    if time >= entry.priceTime {
      entry.price = price
      entry.priceTime = time
    }
    entries[ticker] = entry
    return quote(ticker, entry)
  }

  /// Record a trade; returns nothing until the previous close is known.
  func trade(ticker: String, price: Double, time: Double) -> Quote? {
    var entry = entries[ticker] ?? Entry()
    guard time >= entry.priceTime else { return nil }
    entry.price = price
    entry.priceTime = time
    entries[ticker] = entry
    return quote(ticker, entry)
  }

  private func quote(_ ticker: String, _ entry: Entry) -> Quote? {
    guard entry.price > 0, entry.prevClose > 0 else { return nil }
    return Quote(symbol: Market.us.rawValue + ticker, name: ticker, price: entry.price, prevClose: entry.prevClose)
  }
}
