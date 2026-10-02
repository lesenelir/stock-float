import Foundation
import Testing

@testable import StockFloat

@Test func keepsTheLatestTradePerTicker() {
  let frame = Data(
    """
    {"type":"trade","data":[
      {"s":"AAPL","p":333.10,"t":1791000000500,"v":10,"c":["1"]},
      {"s":"NVDA","p":235.04,"t":1791000000100,"v":5},
      {"s":"AAPL","p":333.27,"t":1791000000900,"v":20},
      {"s":"AAPL","p":333.00,"t":1791000000200,"v":1}
    ]}
    """.utf8)

  #expect(
    FinnhubProvider.latestTrades(in: frame) == [
      FinnhubTrade(s: "AAPL", p: 333.27, t: 1_791_000_000_900),
      FinnhubTrade(s: "NVDA", p: 235.04, t: 1_791_000_000_100),
    ])
}

@Test func ignoresNonTradeFrames() {
  #expect(FinnhubProvider.latestTrades(in: Data(#"{"type":"ping"}"#.utf8)).isEmpty)
  #expect(FinnhubProvider.latestTrades(in: Data(#"{"type":"error","msg":"Invalid API key"}"#.utf8)).isEmpty)
  #expect(FinnhubProvider.latestTrades(in: Data("not json".utf8)).isEmpty)
}

@Test func tradesWaitForThePreviousClose() async {
  let book = FinnhubBook()

  #expect(await book.trade(ticker: "AAPL", price: 333, time: 100) == nil)
  // The snapshot is older than the trade, so it supplies only the previous close.
  #expect(
    await book.reference(ticker: "AAPL", price: 331, prevClose: 330, time: 50)
      == Quote(symbol: "usAAPL", name: "AAPL", price: 333, prevClose: 330, time: Date(timeIntervalSince1970: 100)))
  #expect(
    await book.trade(ticker: "AAPL", price: 334, time: 101)
      == Quote(symbol: "usAAPL", name: "AAPL", price: 334, prevClose: 330, time: Date(timeIntervalSince1970: 101)))
}

@Test func staleTradesAndUnknownTickersAreDropped() async {
  let book = FinnhubBook()

  #expect(
    await book.reference(ticker: "AAPL", price: 333, prevClose: 330, time: 200)
      == Quote(symbol: "usAAPL", name: "AAPL", price: 333, prevClose: 330, time: Date(timeIntervalSince1970: 200)))
  #expect(await book.trade(ticker: "AAPL", price: 320, time: 150) == nil)
  // Finnhub answers an unknown ticker with zeros.
  #expect(await book.reference(ticker: "NOPE", price: 0, prevClose: 0, time: 0) == nil)
}
