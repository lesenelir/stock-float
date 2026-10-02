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
  #expect(config.language == .system)
  #expect(config.hotkey == "ctrl+opt+s")
  #expect(config.textSize == .small)
  #expect(config.opacity == 1)
}

@Test(arguments: [("green", Config.UpColor.green), ("red", .red), ("mono", .mono)])
func readsEveryColorScheme(raw: String, color: Config.UpColor) throws {
  let config = try JSONDecoder().decode(Config.self, from: Data(#"{"upColor":"\#(raw)"}"#.utf8))

  #expect(config.upColor == color)
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
  config.clickThrough = true
  config.language = .en
  config.hotkey = "cmd+shift+9"
  config.textSize = .large
  config.opacity = 0.7

  try config.save(to: url)

  #expect(Config.load(from: url) == config)
}
