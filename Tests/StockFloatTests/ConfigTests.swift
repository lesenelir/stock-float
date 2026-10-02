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
}

@Test func roundTripsThroughDisk() throws {
  let url = FileManager.default.temporaryDirectory.appending(path: "stock-float-\(UUID().uuidString)/config.json")
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  var config = Config()
  config.symbols = ["hk00700"]
  config.upColor = .red
  config.clickThrough = true

  try config.save(to: url)

  #expect(Config.load(from: url) == config)
}
