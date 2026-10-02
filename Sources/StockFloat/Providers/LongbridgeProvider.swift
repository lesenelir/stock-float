import Foundation
import os

/// Streams US quotes, including pre-market, post-market and overnight prices, from the official Longbridge CLI.
///
/// `longbridge serve` keeps one market WebSocket open and speaks newline-delimited JSON-RPC on stdin/stdout;
/// the CLI owns the OAuth token, so no Longbridge credential is stored here.
struct LongbridgeProvider: QuoteProvider {
  // GUI apps do not inherit the shell's PATH, so the usual install locations are checked directly.
  static let defaultSearchPaths = ["/opt/homebrew/bin/longbridge", "/usr/local/bin/longbridge"]

  var searchPaths = LongbridgeProvider.defaultSearchPaths
  /// Seconds between full-quote refreshes, which correct the previous close and each session's base.
  var reconcileInterval: Double = 15

  func events(for symbols: [StockSymbol]) -> AsyncStream<QuoteEvent> {
    AsyncStream { continuation in
      let task = Task {
        var backoff = 1.0
        while !Task.isCancelled {
          let established = await serve(symbols, continuation)
          backoff = established ? 1 : min(backoff * 2, 60)
          try? await Task.sleep(for: .seconds(backoff))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Run one `longbridge serve` process until it exits; returns whether it ever delivered a snapshot.
  private func serve(_ symbols: [StockSymbol], _ continuation: AsyncStream<QuoteEvent>.Continuation) async -> Bool {
    guard let path = searchPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      continuation.yield(.offline(Self.outage(executableFound: false, detail: "")))
      return false
    }

    // Writing to a CLI that has already exited must fail with an error, not kill this process.
    signal(SIGPIPE, SIG_IGN)

    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["serve"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    do {
      try process.run()
    } catch {
      continuation.yield(.offline(Self.outage(executableFound: true, detail: error.localizedDescription)))
      return false
    }

    let remoteSymbols = symbols.map(Self.remoteSymbol)
    let established = OSAllocatedUnfairLock(initialState: false)
    let lastSnapshot = OSAllocatedUnfairLock(initialState: ContinuousClock.now)
    let failure = OSAllocatedUnfairLock(initialState: "")
    let writer = input.fileHandleForWriting
    let reader = output.fileHandleForReading
    let errorReader = errors.fileHandleForReading

    let requester = Task {
      do {
        try writer.write(contentsOf: Self.request(id: 1, method: "quote.subscribe", symbols: remoteSymbols))
        var id = 2
        // A CLI that stops answering is restarted rather than left showing stale prices.
        while ContinuousClock.now - lastSnapshot.withLock({ $0 }) < .seconds(reconcileInterval * 3) {
          try writer.write(contentsOf: Self.request(id: id, method: "quote.quote", symbols: remoteSymbols))
          id += 1
          try await Task.sleep(for: .seconds(reconcileInterval))
        }
      } catch {}
      process.terminate()
    }

    // Both readers run until the process exits and closes its pipes.
    await withTaskCancellationHandler {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          var book = LongbridgeBook()
          for await line in Self.lines(from: reader) {
            switch LongbridgeMessage(line: line) {
            case .snapshot(let quotes):
              established.withLock { $0 = true }
              lastSnapshot.withLock { $0 = .now }
              continuation.yield(.online)
              for quote in quotes.compactMap({ book.apply($0) }) {
                continuation.yield(.quote(quote))
              }
            case .tick(let tick):
              if let quote = book.apply(tick) {
                continuation.yield(.quote(quote))
              }
            case .failure(let message):
              failure.withLock { $0 = message }
              continuation.yield(.offline(Self.outage(executableFound: true, detail: message)))
            case .other:
              break
            }
          }
        }
        // Draining stderr keeps the CLI from blocking on a full pipe; its last line explains an early exit.
        group.addTask {
          for await line in Self.lines(from: errorReader) where !line.isEmpty {
            failure.withLock { $0 = line }
          }
        }
      }
    } onCancel: {
      process.terminate()
    }
    requester.cancel()
    process.terminate()
    try? writer.close()

    continuation.yield(.offline(Self.outage(executableFound: true, detail: failure.withLock { $0 })))
    return established.withLock { $0 }
  }

  /// The lines written to a pipe, ending when its writer closes it.
  ///
  /// `FileHandle.bytes` is not used: its reads from every handle share one actor and block it, so an idle
  /// stderr would stall stdout.
  private static func lines(from handle: FileHandle) -> AsyncStream<String> {
    AsyncStream { continuation in
      let pending = OSAllocatedUnfairLock(initialState: Data())
      handle.readabilityHandler = { handle in
        let chunk = handle.availableData
        let complete = pending.withLock { buffer -> [Data] in
          buffer.append(chunk)
          var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
          // Whatever follows the last newline is an unfinished line, unless the pipe just closed.
          buffer = chunk.isEmpty ? Data() : Data(lines.removeLast())
          return lines.map { Data($0) }
        }
        for line in complete where !line.isEmpty {
          continuation.yield(String(decoding: line, as: UTF8.self))
        }
        if chunk.isEmpty {
          handle.readabilityHandler = nil
          continuation.finish()
        }
      }
      continuation.onTermination = { _ in handle.readabilityHandler = nil }
    }
  }

  static func remoteSymbol(_ symbol: StockSymbol) -> String {
    symbol.code + ".US"
  }

  /// One JSON-RPC request line, newline included.
  static func request(id: Int, method: String, symbols: [String]) throws -> Data {
    struct Request: Encodable {
      struct Params: Encodable {
        let symbols: [String]
      }

      let jsonrpc = "2.0"
      let id: Int
      let method: String
      let params: Params
    }

    var line = try JSONEncoder().encode(Request(id: id, method: method, params: .init(symbols: symbols)))
    line.append(0x0A)
    return line
  }

  /// Classify an outage from `detail`, the CLI's last stderr line or an RPC error message.
  static func outage(executableFound: Bool, detail: String) -> Outage {
    guard executableFound else { return .longbridgeMissing }
    if detail.contains("auth login") {
      return .longbridgeLoggedOut
    }
    return detail.isEmpty ? .unreachable : .longbridge(detail)
  }
}

// MARK: Wire format

/// One line from `longbridge serve`, reduced to what the provider acts on.
enum LongbridgeMessage: Equatable {
  /// Full quotes, from `quote.subscribe` or `quote.quote`.
  case snapshot([LongbridgeQuote])
  /// A `quote.updated` push.
  case tick(LongbridgeTick)
  case failure(String)
  case other

  init(line: String) {
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(line.utf8)) else {
      self = .other
      return
    }
    if let error = envelope.error {
      self = .failure(error.message)
    } else if envelope.method == "quote.updated", let tick = envelope.params {
      self = .tick(tick)
    } else if let quotes = envelope.result?.quotes {
      self = .snapshot(quotes)
    } else {
      self = .other
    }
  }

  private struct Envelope: Decodable {
    struct RPCError: Decodable {
      let message: String
    }

    // `quote.quote` answers with a bare array, `quote.subscribe` with an object holding `quotes`.
    struct Result: Decodable {
      let quotes: [LongbridgeQuote]?

      init(from decoder: Decoder) throws {
        if let quotes = try? decoder.singleValueContainer().decode([LongbridgeQuote].self) {
          self.quotes = quotes
        } else {
          let container = try decoder.container(keyedBy: CodingKeys.self)
          quotes = try container.decodeIfPresent([LongbridgeQuote].self, forKey: .quotes)
        }
      }

      private enum CodingKeys: String, CodingKey {
        case quotes
      }
    }

    let method: String?
    let params: LongbridgeTick?
    let result: Result?
    let error: RPCError?

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      method = try container.decodeIfPresent(String.self, forKey: .method)
      error = try container.decodeIfPresent(RPCError.self, forKey: .error)
      // Other notifications and results have shapes this provider does not model.
      params = try? container.decodeIfPresent(LongbridgeTick.self, forKey: .params)
      result = try? container.decodeIfPresent(Result.self, forKey: .result)
    }

    private enum CodingKeys: String, CodingKey {
      case method, params, result, error
    }
  }
}

/// A price with the time it traded.
struct LongbridgePrice: Decodable, Equatable {
  var price: Double
  var time: Date

  init(price: Double, time: Date) {
    self.price = price
    self.time = time
  }

  init(from decoder: Decoder) throws {
    self = try decoder.container(keyedBy: WireKey.self).price()
  }
}

/// The OpenAPI `SecurityQuote`: the regular session plus the latest price of each extended session.
struct LongbridgeQuote: Decodable, Equatable {
  let symbol: String
  let last: LongbridgePrice
  let prevClose: Double
  let sessions: [ExtendedQuote.Session: LongbridgePrice]

  init(symbol: String, last: LongbridgePrice, prevClose: Double, sessions: [ExtendedQuote.Session: LongbridgePrice] = [:]) {
    self.symbol = symbol
    self.last = last
    self.prevClose = prevClose
    self.sessions = sessions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: WireKey.self)
    symbol = try container.decode(String.self, forKey: .symbol)
    last = try container.price()
    prevClose = try container.number(.prevClose)
    var sessions: [ExtendedQuote.Session: LongbridgePrice] = [:]
    sessions[.pre] = try container.decodeIfPresent(LongbridgePrice.self, forKey: .preMarketQuote)
    sessions[.post] = try container.decodeIfPresent(LongbridgePrice.self, forKey: .postMarketQuote)
    sessions[.overnight] = try container.decodeIfPresent(LongbridgePrice.self, forKey: .overnightQuote)
    self.sessions = sessions
  }
}

/// A `quote.updated` push: the latest price of whichever session is trading.
struct LongbridgeTick: Decodable, Equatable {
  let symbol: String
  let last: LongbridgePrice
  /// `nil` for the regular session.
  let session: ExtendedQuote.Session?

  init(symbol: String, last: LongbridgePrice, session: ExtendedQuote.Session?) {
    self.symbol = symbol
    self.last = last
    self.session = session
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: WireKey.self)
    symbol = try container.decode(String.self, forKey: .symbol)
    last = try container.price()
    switch try container.decode(String.self, forKey: .tradeSession) {
    case "Intraday": session = nil
    case "Pre": session = .pre
    case "Post": session = .post
    case "Overnight": session = .overnight
    case let other:
      throw DecodingError.dataCorruptedError(
        forKey: .tradeSession, in: container, debugDescription: "Unknown trade session \(other)")
    }
  }
}

private enum WireKey: String, CodingKey {
  case symbol
  case lastDone = "last_done"
  case prevClose = "prev_close"
  case timestamp
  case tradeSession = "trade_session"
  case preMarketQuote = "pre_market_quote"
  case postMarketQuote = "post_market_quote"
  case overnightQuote = "overnight_quote"
}

extension KeyedDecodingContainer<WireKey> {
  // The CLI serializes decimals as strings; accept numbers too in case that changes.
  fileprivate func number(_ key: WireKey) throws -> Double {
    if let text = try? decode(String.self, forKey: key) {
      guard let value = Double(text) else {
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a number: \(text)")
      }
      return value
    }
    return try decode(Double.self, forKey: key)
  }

  fileprivate func price() throws -> LongbridgePrice {
    let text = try decode(String.self, forKey: .timestamp)
    guard let time = rfc3339.date(from: text) ?? rfc3339Fractional.date(from: text) else {
      throw DecodingError.dataCorruptedError(
        forKey: .timestamp, in: self, debugDescription: "Not an RFC 3339 time: \(text)")
    }
    return LongbridgePrice(price: try number(.lastDone), time: time)
  }
}

// ISO8601DateFormatter is documented as thread-safe but is not marked Sendable.
private nonisolated(unsafe) let rfc3339 = ISO8601DateFormatter()
private nonisolated(unsafe) let rfc3339Fractional: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

// MARK: Merging

/// Merges snapshots and pushes into quotes, keeping whichever price is newer per session.
struct LongbridgeBook {
  private struct Entry {
    var regular: LongbridgePrice?
    var prevClose = 0.0
    var sessions: [ExtendedQuote.Session: LongbridgePrice] = [:]
  }

  private var entries: [String: Entry] = [:]

  mutating func apply(_ snapshot: LongbridgeQuote) -> Quote? {
    var entry = entries[snapshot.symbol] ?? Entry()
    if snapshot.last.time >= entry.regular?.time ?? .distantPast {
      entry.regular = snapshot.last
    }
    entry.prevClose = snapshot.prevClose
    for (session, incoming) in snapshot.sessions where incoming.time >= entry.sessions[session]?.time ?? .distantPast {
      entry.sessions[session] = incoming
    }
    entries[snapshot.symbol] = entry
    return quote(snapshot.symbol, entry)
  }

  /// Returns nothing for a push older than what is already held, or one that arrives before the first snapshot.
  mutating func apply(_ tick: LongbridgeTick) -> Quote? {
    var entry = entries[tick.symbol] ?? Entry()
    let stored = tick.session.map { entry.sessions[$0] } ?? entry.regular
    guard tick.last.time >= stored?.time ?? .distantPast else { return nil }
    if let session = tick.session {
      entry.sessions[session] = tick.last
    } else {
      entry.regular = tick.last
    }
    entries[tick.symbol] = entry
    return quote(tick.symbol, entry)
  }

  private func quote(_ remoteSymbol: String, _ entry: Entry) -> Quote? {
    guard let regular = entry.regular, entry.prevClose > 0, remoteSymbol.hasSuffix(".US") else { return nil }
    let ticker = String(remoteSymbol.dropLast(3))
    // The extended session shown is the most recent one, and only while it is newer than the regular price.
    let latest = entry.sessions
      .filter { $0.value.time > regular.time }
      .max { $0.value.time < $1.value.time }
    // Its change is measured against the regular price it follows, which is unambiguous in every session;
    // the feed's own per-session `prev_close` could not be told apart from the day's previous close.
    return Quote(
      symbol: Market.us.rawValue + ticker,
      name: ticker,
      price: regular.price,
      prevClose: entry.prevClose,
      extended: latest.map { ExtendedQuote(session: $0.key, price: $0.value.price, prevClose: regular.price) }
    )
  }
}
