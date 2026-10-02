enum QuoteEvent: Equatable, Sendable {
  case quote(Quote)
  /// Whether the provider can currently reach its data source.
  case connection(Bool)
}

protocol QuoteProvider: Sendable {
  /// Emit quotes for `symbols` until the consumer stops iterating the stream.
  func events(for symbols: [StockSymbol]) -> AsyncStream<QuoteEvent>
}
