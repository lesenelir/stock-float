import Foundation
import Testing

@testable import StockFloat

@MainActor
@Test func theStoreSetsOffEachAlertOnce() throws {
  let url = FileManager.default.temporaryDirectory.appending(path: "stockfloat-\(UUID().uuidString)/config.json")
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  var config = Config()
  config.symbols = ["usAAPL", "usNVDA"]
  config.alerts = [
    PriceAlert(symbol: "usAAPL", price: 200, below: false),
    PriceAlert(symbol: "usAAPL", price: 150, below: true),
    PriceAlert(symbol: "usNVDA", price: 200, below: false),
  ]
  let store = QuoteStore(config: config, savingTo: url)
  var fired: [PriceAlert] = []
  store.onAlert = { _, hits in fired += hits }

  store.apply(.quote(Quote(symbol: "usAAPL", name: "AAPL", price: 190, prevClose: 180)), from: .tencent)
  #expect(fired.isEmpty)
  // An extended-hours price counts: it is the newest.
  store.apply(
    .quote(
      Quote(
        symbol: "usAAPL", name: "AAPL", price: 190, prevClose: 180,
        extended: ExtendedQuote(session: .post, price: 201, prevClose: 190))),
    from: .longbridge)
  store.apply(.quote(Quote(symbol: "usAAPL", name: "AAPL", price: 205, prevClose: 180)), from: .longbridge)

  #expect(fired == [PriceAlert(symbol: "usAAPL", price: 200, below: false)])
  let left = [PriceAlert(symbol: "usAAPL", price: 150, below: true), PriceAlert(symbol: "usNVDA", price: 200, below: false)]
  #expect(store.config.alerts == left)
  #expect(Config.load(from: url).alerts == left)
}

@Test func notificationsSayWhatHappened() {
  let zh = Strings(language: .zh)
  let en = Strings(language: .en)

  #expect(en.alertTitle("AAPL", below: false, "200.00") == "AAPL rose to 200.00")
  #expect(zh.alertTitle("腾讯控股", below: true, "400.00") == "腾讯控股 跌到 400.00")
  #expect(en.alertBody(session: nil, "201.30", "+2.15%") == "Now 201.30 (+2.15%)")
  #expect(en.alertBody(session: .post, "334.00", "+0.22%") == "Post 334.00 (+0.22%)")
}
