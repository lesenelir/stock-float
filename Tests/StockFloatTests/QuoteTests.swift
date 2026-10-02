import Foundation
import Testing

@testable import StockFloat

@Test func aPriceGoesStaleAfterHalfAnHour() {
  let traded = Date(timeIntervalSince1970: 1_000_000)
  let quote = Quote(symbol: "usAAPL", name: "AAPL", price: 333, prevClose: 330, time: traded)

  #expect(!quote.isStale(at: traded))
  #expect(!quote.isStale(at: traded.addingTimeInterval(30 * 60)))
  #expect(quote.isStale(at: traded.addingTimeInterval(30 * 60 + 1)))
}

@Test func aPriceWithoutATimeIsNotCalledStale() {
  let quote = Quote(symbol: "usAAPL", name: "AAPL", price: 333, prevClose: 330)

  #expect(!quote.isStale(at: .distantFuture))
}
