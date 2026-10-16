import Foundation

/// User settings, stored as JSON at `~/.config/stock-float/config.json`.
struct Config: Codable, Equatable, Sendable {
  enum UpColor: String, Codable, CaseIterable, Sendable {
    case green, red
    /// No red or green: the sign alone tells a gain from a loss.
    case mono
  }

  enum TextSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    /// Multiplier for fonts and the panel width.
    var scale: Double {
      switch self {
      case .small: 1
      case .medium: 1.15
      case .large: 1.3
      }
    }
  }

  static let opacityChoices = [1.0, 0.85, 0.7, 0.5]

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
  /// Global shortcut that hides and shows the panel, written like `ctrl+opt+s`; empty disables it.
  var hotkey = "ctrl+opt+s"
  var textSize = TextSize.small
  /// Opacity of the whole panel, 0.3 to 1.
  var opacity = 1.0
  /// Show the app in the Dock (and the ⌘Tab switcher); the menu bar icon is always there.
  var dockIcon = true
  /// Price alerts waiting to go off, for symbols of the watch list.
  var alerts: [PriceAlert] = []

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
    hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey
    textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? defaults.textSize
    opacity = min(1, max(0.3, try container.decodeIfPresent(Double.self, forKey: .opacity) ?? defaults.opacity))
    dockIcon = try container.decodeIfPresent(Bool.self, forKey: .dockIcon) ?? defaults.dockIcon
    // An alert that cannot be read is dropped, not the whole config.
    alerts = ((try? container.decodeIfPresent([PriceAlert].self, forKey: .alerts)) ?? []).filter { $0.price > 0 }
    dropOrphanAlerts()
  }

  /// Remove the alerts of symbols no longer watched, which no feed would set off.
  mutating func dropOrphanAlerts() {
    alerts.removeAll { !symbols.contains($0.symbol) }
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

/// Notifies once when a symbol's price reaches `price`, then goes away.
struct PriceAlert: Codable, Hashable, Sendable {
  /// `StockSymbol.id` of the instrument.
  var symbol: String
  var price: Double
  /// Waits for the price to fall to `price`; otherwise for it to rise to it.
  var below: Bool

  /// Whether `latest` sets the alert off. Zero is no price.
  func isReached(by latest: Double) -> Bool {
    guard latest > 0 else { return false }
    return below ? latest <= price : latest >= price
  }

  /// Read a price as typed, which must be above zero.
  static func parsePrice(_ text: String) -> Double? {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
    guard let price = Double(cleaned), price > 0, price.isFinite else { return nil }
    return price
  }
}
