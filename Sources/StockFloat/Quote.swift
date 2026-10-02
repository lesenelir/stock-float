import Foundation

enum Market: String, CaseIterable, Sendable {
  case us, hk, sh, sz
}

/// A watch-list entry, written as a market prefix plus code: `usAAPL`, `hk00700`, `sh600519`.
struct StockSymbol: Hashable, Sendable {
  let market: Market
  let code: String

  var id: String { market.rawValue + code }

  /// Parse the canonical prefixed form only.
  init?(id: String) {
    guard let market = Market.allCases.first(where: { id.hasPrefix($0.rawValue) }) else { return nil }
    let code = String(id.dropFirst(market.rawValue.count))
    guard Self.isValid(code, in: market) else { return nil }
    self.market = market
    self.code = code
  }

  /// Parse user input: the prefixed form, a bare US ticker (`aapl`), or a bare HK / A-share number.
  init?(_ input: String) {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let symbol = StockSymbol(id: text) {
      self = symbol
      return
    }
    if text.allSatisfy(\.isASCIIDigit) {
      switch text.count {
      case 5: self.init(id: "hk" + text)
      case 6: self.init(id: ("569".contains(text.prefix(1)) ? "sh" : "sz") + text)
      default: return nil
      }
      return
    }
    self.init(id: "us" + text.uppercased())
  }

  // The prefix must be followed by an uppercase letter for US so a bare ticker like `usb` is not read as `us` + `B`.
  private static func isValid(_ code: String, in market: Market) -> Bool {
    guard !code.isEmpty else { return false }
    switch market {
    case .us:
      return code.first?.isUppercaseASCIILetter == true
        && code.allSatisfy { $0.isUppercaseASCIILetter || $0.isASCIIDigit || $0 == "." || $0 == "-" }
    case .hk, .sh, .sz:
      return code.allSatisfy(\.isASCIIDigit)
    }
  }
}

struct Quote: Equatable, Sendable {
  /// `StockSymbol.id` of the instrument.
  let symbol: String
  var name: String
  /// Last price of the regular session.
  var price: Double
  var prevClose: Double
  /// Set while a pre-market, post-market or overnight price is newer than the regular one.
  var extended: ExtendedQuote?
  /// When the newest price shown was traded or quoted, if the source says.
  var time: Date?

  /// How long a price can go without an update before it is shown as stale.
  static let staleAfter: TimeInterval = 30 * 60

  /// Change against the previous close, in percent.
  var changePercent: Double {
    percentChange(of: price, from: prevClose)
  }

  /// Whether the price is old enough to be misleading; unknown times are not treated as stale.
  func isStale(at now: Date) -> Bool {
    guard let time else { return false }
    return now.timeIntervalSince(time) > Self.staleAfter
  }
}

/// A price from outside the regular session.
struct ExtendedQuote: Equatable, Sendable {
  enum Session: String, CaseIterable, Sendable {
    case pre, post, overnight
  }

  let session: Session
  var price: Double
  /// The close this session's change is measured against.
  var prevClose: Double

  /// Change against `prevClose`, in percent.
  var changePercent: Double {
    percentChange(of: price, from: prevClose)
  }
}

private func percentChange(of price: Double, from base: Double) -> Double {
  base > 0 ? (price / base - 1) * 100 : 0
}

private extension Character {
  var isASCIIDigit: Bool { isASCII && isNumber }
  var isUppercaseASCIILetter: Bool { isASCII && isLetter && isUppercase }
}
