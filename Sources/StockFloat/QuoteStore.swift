import Foundation
import Observation

/// Owns the config and the latest quotes, and runs the providers that feed them.
@MainActor
@Observable
final class QuoteStore {
  private(set) var config: Config
  private(set) var quotes: [String: Quote] = [:]
  /// Data sources that are currently unreachable, and why.
  private(set) var offlineSources: [String: Outage] = [:]

  @ObservationIgnored private var tasks: [Task<Void, Never>] = []

  init(config: Config) {
    self.config = config
  }

  /// The interface strings for the configured language.
  var strings: Strings {
    Strings(language: config.language.resolved())
  }

  /// (Re)start the feeds for the configured symbols.
  func start() {
    tasks.forEach { $0.cancel() }
    tasks = []
    offlineSources = [:]
    // Dropping the old quotes keeps a stale extended-hours line from outliving a change of data source.
    quotes = [:]

    var symbols = config.symbols.compactMap(StockSymbol.init(id:))
    let usSymbols = symbols.filter { $0.market == .us }
    if config.longbridge {
      run(LongbridgeProvider(), named: "Longbridge", for: usSymbols)
      symbols.removeAll { $0.market == .us }
    } else if !config.finnhubKey.isEmpty {
      run(FinnhubProvider(apiKey: config.finnhubKey), named: "Finnhub", for: usSymbols)
      symbols.removeAll { $0.market == .us }
    }
    run(TencentProvider(pollSeconds: config.pollSeconds), named: "Tencent", for: symbols)
  }

  /// Apply and persist a config change, restarting the feeds when it affects them.
  func update(_ change: (inout Config) -> Void) {
    var updated = config
    change(&updated)
    guard updated != config else { return }
    let feedsChanged =
      updated.symbols != config.symbols
      || updated.longbridge != config.longbridge
      || updated.finnhubKey != config.finnhubKey
      || updated.pollSeconds != config.pollSeconds
    config = updated
    try? updated.save()
    if feedsChanged {
      start()
    }
  }

  private func run(_ provider: some QuoteProvider, named name: String, for symbols: [StockSymbol]) {
    guard !symbols.isEmpty else { return }
    let task = Task { [weak self] in
      for await event in provider.events(for: symbols) {
        guard !Task.isCancelled else { return }
        self?.apply(event, from: name)
      }
    }
    tasks.append(task)
  }

  private func apply(_ event: QuoteEvent, from source: String) {
    switch event {
    case .quote(let quote):
      quotes[quote.symbol] = quote
    case .online:
      offlineSources[source] = nil
    case .offline(let outage):
      offlineSources[source] = outage
    }
  }
}
