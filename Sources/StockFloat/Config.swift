import Foundation

/// User settings, stored as JSON at `~/.config/stock-float/config.json`.
struct Config: Codable, Equatable, Sendable {
  enum UpColor: String, Codable, Sendable {
    case green, red
  }

  /// `StockSymbol.id` values, in display order.
  var symbols = ["usAAPL", "usNVDA", "usTSLA"]
  /// Take US quotes from the Longbridge CLI, which adds pre-market, post-market and overnight prices.
  var longbridge = false
  /// Used for US quotes when Longbridge is off; empty falls back to the Tencent feed.
  var finnhubKey = ""
  var pollSeconds = 3.0
  var upColor = UpColor.green
  var clickThrough = false
  var language = LanguageSetting.system

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Config()
    symbols =
      try container.decodeIfPresent([String].self, forKey: .symbols).map { Self.parseSymbols($0).ids }
      ?? defaults.symbols
    longbridge = try container.decodeIfPresent(Bool.self, forKey: .longbridge) ?? defaults.longbridge
    finnhubKey = try container.decodeIfPresent(String.self, forKey: .finnhubKey) ?? defaults.finnhubKey
    pollSeconds = max(1, try container.decodeIfPresent(Double.self, forKey: .pollSeconds) ?? defaults.pollSeconds)
    upColor = try container.decodeIfPresent(UpColor.self, forKey: .upColor) ?? defaults.upColor
    clickThrough = try container.decodeIfPresent(Bool.self, forKey: .clickThrough) ?? defaults.clickThrough
    language = try container.decodeIfPresent(LanguageSetting.self, forKey: .language) ?? defaults.language
  }

  /// Normalize user-entered symbols, dropping duplicates; `invalid` lists the entries that could not be read.
  static func parseSymbols(_ entries: [String]) -> (ids: [String], invalid: [String]) {
    var ids: [String] = []
    var invalid: [String] = []
    for entry in entries {
      guard let symbol = StockSymbol(entry) else {
        invalid.append(entry)
        continue
      }
      if !ids.contains(symbol.id) {
        ids.append(symbol.id)
      }
    }
    return (ids, invalid)
  }

  static let fileURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".config/stock-float/config.json")

  /// Read the config, writing the defaults on first run. An unreadable file is left untouched.
  static func load(from url: URL = fileURL) -> Config {
    guard let data = try? Data(contentsOf: url) else {
      let config = Config()
      try? config.save(to: url)
      return config
    }
    return (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
  }

  func save(to url: URL = fileURL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
