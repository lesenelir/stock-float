import Foundation
import Testing

@testable import StockFloat

@Test(arguments: [
  ("usAAPL", "usAAPL"),
  ("aapl", "usAAPL"),
  (" BRK.B ", "usBRK.B"),
  ("usb", "usUSB"),
  ("hk00700", "hk00700"),
  ("00700", "hk00700"),
  ("600519", "sh600519"),
  ("000001", "sz000001"),
  ("300750", "sz300750"),
])
func normalizesSymbolInput(input: String, id: String) {
  #expect(StockSymbol(input)?.id == id)
}

@Test(arguments: ["", "   ", "1234", "AAPL&x=1", "a b", "苹果"])
func rejectsUnreadableSymbols(input: String) {
  #expect(StockSymbol(input) == nil)
}

@Test func parseSymbolsDeduplicatesAndReportsInvalidEntries() {
  let parsed = Config.parseSymbols(["aapl", "usAAPL", "hk00700", "a b"])

  #expect(parsed.ids == ["usAAPL", "hk00700"])
  #expect(parsed.invalid == ["a b"])
}

@Test func missingKeysFallBackToDefaults() throws {
  let config = try JSONDecoder().decode(Config.self, from: Data(#"{"symbols":["nvda"],"pollSeconds":0.1}"#.utf8))

  #expect(config.symbols == ["usNVDA"])
  #expect(config.pollSeconds == 1)
  #expect(config.finnhubKey.isEmpty)
  #expect(config.upColor == .green)
  #expect(config.greenShade == .system && config.redShade == .system)
  #expect(config.language == .system)
  #expect(config.hotkey == "ctrl+opt+s")
  #expect(config.textSize == .small)
  #expect(config.opacity == 1)
  #expect(config.dockIcon)
  #expect(config.flash)
}

@Test(arguments: [("green", Config.UpColor.green), ("red", .red), ("mono", .mono)])
func readsEveryColorScheme(raw: String, color: Config.UpColor) throws {
  let config = try JSONDecoder().decode(Config.self, from: Data(#"{"upColor":"\#(raw)"}"#.utf8))

  #expect(config.upColor == color)
}

@Test func unknownShadesFallBackToTheSystemColors() throws {
  let config = try JSONDecoder().decode(
    Config.self, from: Data(#"{"symbols":["nvda"],"greenShade":"950","redShade":"400"}"#.utf8))

  #expect(config.symbols == ["usNVDA"])
  #expect(config.greenShade == .system)
  #expect(config.redShade == .shade400)
}

@Test(arguments: [(0.0, 0.3), (0.7, 0.7), (5.0, 1.0)])
func keepsOpacityInRange(stored: Double, opacity: Double) throws {
  let config = try JSONDecoder().decode(Config.self, from: Data(#"{"opacity":\#(stored)}"#.utf8))

  #expect(config.opacity == opacity)
}

@Test func roundTripsThroughDisk() throws {
  let url = FileManager.default.temporaryDirectory.appending(path: "stock-float-\(UUID().uuidString)/config.json")
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  var config = Config()
  config.symbols = ["hk00700"]
  config.upColor = .red
  config.greenShade = .shade400
  config.redShade = .shade600
  config.clickThrough = true
  config.language = .en
  config.hotkey = "cmd+shift+9"
  config.textSize = .large
  config.opacity = 0.7
  config.dockIcon = false
  config.flash = false

  try config.save(to: url)

  #expect(Config.load(from: url) == config)
}

@Test func alertsGoOffAtTheirPriceOrBeyond() {
  let rise = PriceAlert(symbol: "usAAPL", price: 200, below: false)
  let fall = PriceAlert(symbol: "usAAPL", price: 200, below: true)

  #expect(!rise.isReached(by: 199.99) && fall.isReached(by: 199.99))
  #expect(rise.isReached(by: 200) && fall.isReached(by: 200))
  #expect(rise.isReached(by: 200.01) && !fall.isReached(by: 200.01))
  // Zero is no price.
  #expect(!rise.isReached(by: 0) && !fall.isReached(by: 0))
}

@Test func alertsKeepOnlyWatchedSymbolsAndPrices() throws {
  let json = #"""
    {"symbols":["usAAPL"],"alerts":[
      {"symbol":"usAAPL","price":200,"below":false},
      {"symbol":"usAAPL","price":0,"below":false},
      {"symbol":"usNVDA","price":100,"below":true}]}
    """#
  let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))

  #expect(config.alerts == [PriceAlert(symbol: "usAAPL", price: 200, below: false)])
}

@Test func unreadableAlertsLeaveTheRestOfTheConfig() throws {
  let config = try JSONDecoder().decode(Config.self, from: Data(#"{"symbols":["msft"],"alerts":"no"}"#.utf8))

  #expect(config.symbols == ["usMSFT"])
  #expect(config.alerts.isEmpty)
}

@Test(arguments: [("200", 200.0), (" 1,200.5 ", 1200.5), ("0.051", 0.051)])
func readsTypedPrices(text: String, price: Double) {
  #expect(PriceAlert.parsePrice(text) == price)
}

@Test(arguments: ["", "abc", "0", "-3", "inf", "nan"])
func refusesWhatIsNoPrice(text: String) {
  #expect(PriceAlert.parsePrice(text) == nil)
}
