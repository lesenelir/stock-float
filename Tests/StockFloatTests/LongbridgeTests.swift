import Foundation
import Testing

@testable import StockFloat

private func at(_ seconds: TimeInterval) -> Date {
  Date(timeIntervalSince1970: seconds)
}

private func price(_ price: Double, _ seconds: TimeInterval) -> LongbridgePrice {
  LongbridgePrice(price: price, time: at(seconds))
}

// Times: 100 = previous post-market, 200 = regular close, 300+ = sessions after that close.
private func closedSnapshot(sessions: [ExtendedQuote.Session: LongbridgePrice] = [:]) -> LongbridgeQuote {
  LongbridgeQuote(symbol: "AAPL.US", last: price(333, 200), prevClose: 330, sessions: sessions)
}

// MARK: Wire format

// Captured from `longbridge serve` 0.28.7 during the regular session on 2026-10-02.
@Test func decodesTheSubscribeSnapshot() {
  let line = """
    {"jsonrpc":"2.0","id":1,"result":{"subscribed":[{"symbol":"SOXL.US","fields":["quote"]}],"quotes":[{"symbol":"SOXL.US","last_done":"163.500","prev_close":"153.690","open":"165.200","high":"169.750","low":"162.400","timestamp":"2026-10-02T18:05:47Z","volume":50197187,"turnover":"8330218323.279","trade_status":"Normal","pre_market_quote":{"last_done":"165.290","timestamp":"2026-10-02T13:30:00Z","volume":4183391,"turnover":"679353549.927","high":"166.950","low":"155.370","prev_close":"153.690"},"post_market_quote":{"last_done":"154.760","timestamp":"2026-10-01T23:59:58Z","volume":765074,"turnover":"117794136.068","high":"155.300","low":"152.880","prev_close":"153.690"},"overnight_quote":{"last_done":"159.040","timestamp":"2026-10-02T08:00:00Z","volume":3081463,"turnover":"481061481.000","high":"159.610","low":"153.510","prev_close":"153.690"}}]}}
    """
  let expected = LongbridgeQuote(
    symbol: "SOXL.US",
    last: price(163.5, 1_790_964_347),
    prevClose: 153.69,
    sessions: [
      .pre: price(165.29, 1_790_947_800),
      .post: price(154.76, 1_790_899_198),
      .overnight: price(159.04, 1_790_928_000),
    ])

  #expect(LongbridgeMessage(line: line) == .snapshot([expected]))

  // Every extended price predates the regular one, so a session in progress shows a single line.
  var book = LongbridgeBook()
  #expect(book.apply(expected) == Quote(symbol: "usSOXL", name: "SOXL", price: 163.5, prevClose: 153.69))
}

@Test func decodesTheQuoteArrayNumericDecimalsAndOtherTimeForms() {
  let line = """
    {"jsonrpc":"2.0","id":2,"result":[{"symbol":"NVDA.US","last_done":235.3,"prev_close":230.86,"timestamp":"2026-10-02T20:00:00+00:00","pre_market_quote":null,"post_market_quote":{"last_done":"236.000","timestamp":"2026-10-02T23:59:58.5Z"}}]}
    """

  #expect(
    LongbridgeMessage(line: line)
      == .snapshot([
        LongbridgeQuote(
          symbol: "NVDA.US", last: price(235.3, 1_790_971_200), prevClose: 230.86,
          sessions: [.post: price(236, 1_790_985_598.5)])
      ]))
}

// Captured from `longbridge serve` 0.28.7, with the session swapped in.
@Test(arguments: [("Intraday", nil), ("Pre", .pre), ("Post", .post), ("Overnight", .overnight)] as [(String, ExtendedQuote.Session?)])
func decodesPushes(wire: String, session: ExtendedQuote.Session?) {
  let line = """
    {"jsonrpc":"2.0","method":"quote.updated","params":{"last_done":"333.176","open":"333.210","high":"334.540","low":"330.610","timestamp":"2026-10-02T18:05:47Z","volume":18071011,"turnover":"6014100713.242","trade_status":"Normal","trade_session":"\(wire)","current_volume":0,"current_turnover":"0","symbol":"AAPL.US"}}
    """

  #expect(
    LongbridgeMessage(line: line)
      == .tick(LongbridgeTick(symbol: "AAPL.US", last: price(333.176, 1_790_964_347), session: session)))
}

@Test func reportsErrorsAndSkipsEverythingElse() {
  #expect(
    LongbridgeMessage(line: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"no quote access"}}"#)
      == .failure("no quote access"))
  #expect(LongbridgeMessage(line: #"{"jsonrpc":"2.0","id":3,"result":null}"#) == .other)
  #expect(LongbridgeMessage(line: #"{"jsonrpc":"2.0","id":1,"result":{"subscribed":[]}}"#) == .other)
  #expect(LongbridgeMessage(line: #"{"jsonrpc":"2.0","method":"quote.depth","params":{"symbol":"AAPL.US"}}"#) == .other)
  #expect(LongbridgeMessage(line: "not json") == .other)
}

@Test func buildsRequestLines() throws {
  let line = try LongbridgeProvider.request(id: 1, method: "quote.subscribe", symbols: ["AAPL.US", "BRK.B.US"])
  let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])

  #expect(line.last == 0x0A)
  #expect(line.dropLast().contains(0x0A) == false)
  #expect(object["jsonrpc"] as? String == "2.0")
  #expect(object["id"] as? Int == 1)
  #expect(object["method"] as? String == "quote.subscribe")
  #expect((object["params"] as? [String: [String]])?["symbols"] == ["AAPL.US", "BRK.B.US"])
}

@Test func mapsSymbolsToLongbridgeNotation() throws {
  #expect(LongbridgeProvider.remoteSymbol(try #require(StockSymbol(id: "usAAPL"))) == "AAPL.US")
  #expect(LongbridgeProvider.remoteSymbol(try #require(StockSymbol(id: "usBRK.B"))) == "BRK.B.US")
}

@Test func classifiesOutages() {
  #expect(LongbridgeProvider.outage(executableFound: false, detail: "") == .longbridgeMissing)
  #expect(
    LongbridgeProvider.outage(
      executableFound: true, detail: "Error: Not authenticated. Please run `longbridge auth login` first.")
      == .longbridgeLoggedOut)
  #expect(LongbridgeProvider.outage(executableFound: true, detail: "no quote access") == .longbridge("no quote access"))
  #expect(LongbridgeProvider.outage(executableFound: true, detail: "") == .unreachable)
}

// MARK: Merging

@Test func showsTheNewestExtendedSessionAgainstTheRegularPrice() {
  var book = LongbridgeBook()

  let quote = book.apply(
    closedSnapshot(sessions: [.pre: price(332, 150), .post: price(334, 300), .overnight: price(335, 400)]))

  #expect(quote?.price == 333)
  #expect(quote?.prevClose == 330)
  #expect(quote?.extended == ExtendedQuote(session: .overnight, price: 335, prevClose: 333))
}

@Test func pushesUpdateTheirOwnSession() {
  var book = LongbridgeBook()
  _ = book.apply(closedSnapshot(sessions: [.post: price(331, 100)]))

  // The first post-market trade after the close replaces the previous day's.
  let post = book.apply(LongbridgeTick(symbol: "AAPL.US", last: price(334.5, 310), session: .post))
  #expect(post?.extended == ExtendedQuote(session: .post, price: 334.5, prevClose: 333))
  #expect(post?.price == 333)

  #expect(book.apply(LongbridgeTick(symbol: "AAPL.US", last: price(1, 305), session: .post)) == nil)

  // A snapshot older than the push keeps the pushed price.
  let reconciled = book.apply(closedSnapshot(sessions: [.post: price(334.2, 308)]))
  #expect(reconciled?.extended?.price == 334.5)

  // The next regular session opens: its price is newer than every extended one, so the second line goes away.
  let regular = book.apply(LongbridgeTick(symbol: "AAPL.US", last: price(336, 500), session: nil))
  #expect(regular == Quote(symbol: "usAAPL", name: "AAPL", price: 336, prevClose: 330))
}

@Test func pushesBeforeTheSnapshotAreHeldBack() {
  var book = LongbridgeBook()

  #expect(book.apply(LongbridgeTick(symbol: "AAPL.US", last: price(334, 300), session: .post)) == nil)
  #expect(book.apply(LongbridgeTick(symbol: "AAPL.US", last: price(333.5, 250), session: nil)) == nil)

  let quote = book.apply(closedSnapshot())
  #expect(quote?.price == 333.5)
  #expect(quote?.prevClose == 330)
  #expect(quote?.extended == ExtendedQuote(session: .post, price: 334, prevClose: 333.5))
}

// MARK: Process

/// Write an executable stand-in for the `longbridge` CLI and return its path.
private func fakeCLI(_ script: String) throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appending(path: "stock-float-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let url = directory.appending(path: "longbridge")
  try Data(("#!/bin/sh\n" + script).utf8).write(to: url)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  return url
}

/// Whether the process whose id a fake CLI wrote to `path` is gone within five seconds.
private func hasExited(pidFile path: String) async throws -> Bool {
  // No file means the CLI was stopped before its first line ran.
  guard let text = try? String(contentsOfFile: path, encoding: .utf8),
    let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
  else { return true }
  for _ in 0..<250 {
    if kill(pid, 0) != 0 {
      return true
    }
    try await Task.sleep(for: .milliseconds(20))
  }
  return false
}

private let snapshotLine =
  #"{"jsonrpc":"2.0","id":1,"result":{"subscribed":[],"quotes":[{"symbol":"AAPL.US","last_done":"333.000","prev_close":"330.000","timestamp":"2026-10-02T20:00:00Z"}]}}"#

@Test func talksToTheCLIAndExplainsItsExit() async throws {
  let cli = try fakeCLI(
    """
    echo "$1" > "$0.log"
    read -r line; echo "$line" >> "$0.log"
    echo '\(snapshotLine)'
    read -r line; echo "$line" >> "$0.log"
    echo '{"jsonrpc":"2.0","method":"quote.updated","params":{"symbol":"AAPL.US","last_done":"334.000","timestamp":"2026-10-02T20:05:00Z","trade_session":"Post"}}'
    echo 'Error: Not authenticated. Please run `longbridge auth login` first.' >&2
    exit 1
    """)
  defer { try? FileManager.default.removeItem(at: cli.deletingLastPathComponent()) }
  let symbol = try #require(StockSymbol(id: "usAAPL"))

  var events: [QuoteEvent] = []
  for await event in LongbridgeProvider(searchPaths: [cli.path]).events(for: [symbol]) {
    events.append(event)
    if case .offline = event { break }
  }

  #expect(
    events == [
      .online,
      .quote(Quote(symbol: "usAAPL", name: "AAPL", price: 333, prevClose: 330)),
      .quote(
        Quote(
          symbol: "usAAPL", name: "AAPL", price: 333, prevClose: 330,
          extended: ExtendedQuote(session: .post, price: 334, prevClose: 333))),
      .offline(.longbridgeLoggedOut),
    ])
  let log = try String(contentsOf: URL(fileURLWithPath: cli.path + ".log"), encoding: .utf8)
    .split(separator: "\n")
  #expect(log.count == 3)
  #expect(log.first == "serve")
  #expect(log.dropFirst().first?.contains(#""method":"quote.subscribe""#) == true)
  #expect(log.last?.contains(#""method":"quote.quote""#) == true)
  #expect(log.last?.contains(#""symbols":["AAPL.US"]"#) == true)
}

@Test func reportsAMissingCLI() async throws {
  let symbol = try #require(StockSymbol(id: "usAAPL"))

  let first = await LongbridgeProvider(searchPaths: ["/nonexistent/longbridge"]).events(for: [symbol])
    .first { _ in true }

  #expect(first == .offline(.longbridgeMissing))
}

@Test func stopsTheCLIWhenTheStreamIsDropped() async throws {
  let cli = try fakeCLI(
    """
    echo $$ > "$0.pid"
    echo '\(snapshotLine)'
    exec sleep 600
    """)
  defer { try? FileManager.default.removeItem(at: cli.deletingLastPathComponent()) }
  let symbol = try #require(StockSymbol(id: "usAAPL"))

  let first = await LongbridgeProvider(searchPaths: [cli.path]).events(for: [symbol]).first { _ in true }
  #expect(first == .online)

  #expect(try await hasExited(pidFile: cli.path + ".pid"))
}

// The CLI never answers, so the outcome does not depend on how fast the machine starts it.
@Test func restartsACLIThatStopsAnswering() async throws {
  let cli = try fakeCLI(
    """
    echo $$ > "$0.pid"
    exec sleep 600
    """)
  defer { try? FileManager.default.removeItem(at: cli.deletingLastPathComponent()) }
  let symbol = try #require(StockSymbol(id: "usAAPL"))

  let first = await LongbridgeProvider(searchPaths: [cli.path], reconcileInterval: 0.2).events(for: [symbol])
    .first { _ in true }

  #expect(first == .offline(.unreachable))
  #expect(try await hasExited(pidFile: cli.path + ".pid"))
}
