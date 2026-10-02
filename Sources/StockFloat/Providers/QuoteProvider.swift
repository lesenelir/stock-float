enum QuoteEvent: Equatable, Sendable {
  case quote(Quote)
  /// The provider is receiving data from its source.
  case online
  case offline(Outage)
}

/// Why a data source is unreachable, left untranslated so the interface can word it in its own language.
enum Outage: Hashable, Sendable {
  case unreachable
  case longbridgeMissing
  case longbridgeLoggedOut
  /// An error message from the Longbridge CLI or API, shown as received.
  case longbridge(String)
}

enum QuoteSource: Hashable, Sendable {
  case longbridge, finnhub, tencent
}

protocol QuoteProvider: Sendable {
  /// Emit quotes for `symbols` until the consumer stops iterating the stream.
  func events(for symbols: [StockSymbol]) -> AsyncStream<QuoteEvent>
}
