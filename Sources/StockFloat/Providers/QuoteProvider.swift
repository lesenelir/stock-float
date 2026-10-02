enum QuoteEvent: Equatable, Sendable {
  case quote(Quote)
  /// The provider is receiving data from its source.
  case online
  /// The source is unreachable; `hint` tells the user what to do when the cause is known.
  case offline(hint: String?)
}

protocol QuoteProvider: Sendable {
  /// Emit quotes for `symbols` until the consumer stops iterating the stream.
  func events(for symbols: [StockSymbol]) -> AsyncStream<QuoteEvent>
}
