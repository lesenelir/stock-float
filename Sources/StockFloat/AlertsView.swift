import SwiftUI

/// The price alerts window: the alerts waiting to go off, and a new one being set. It follows the store, so prices
/// and alerts stay current while it is open; an alert goes away once it has notified.
struct AlertsView: View {
  let store: QuoteStore
  let onDone: () -> Void

  @State private var symbol = ""
  @State private var below = false
  @State private var priceText = ""
  @State private var invalid = false

  var body: some View {
    let strings = store.strings
    VStack(alignment: .leading, spacing: 12) {
      if store.config.symbols.isEmpty {
        Text(strings.alertsNeedSymbols)
          .foregroundStyle(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 4) {
          Text(strings.alertSymbol)
          HStack {
            Picker(strings.alertSymbol, selection: $symbol) {
              ForEach(store.config.symbols, id: \.self) { id in
                Text(optionText(id)).tag(id)
              }
            }
            .labelsHidden()
            .fixedSize()
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(strings.alertPrice)
          HStack {
            Picker(strings.alertDirection, selection: $below) {
              Text(strings.alertRises).tag(false)
              Text(strings.alertFalls).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            TextField(latest.map(Format.price) ?? "", text: $priceText)
              .textFieldStyle(.roundedBorder)
            Button(strings.addAlert, action: add)
              .keyboardShortcut(.defaultAction)
          }
          if invalid {
            Text(strings.invalidPrice)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
      }
      Divider()
      if store.config.alerts.isEmpty {
        Text(strings.noAlerts)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      ForEach(store.config.alerts, id: \.self) { alert in
        HStack {
          Text(Format.label(alert.symbol, store.quotes[alert.symbol]))
            .lineLimit(1)
          Spacer()
          Text(strings.alertCondition(below: alert.below, Format.price(alert.price)))
            .monospacedDigit()
          Button(strings.removeAlert) {
            store.update { $0.alerts.removeAll { $0 == alert } }
          }
        }
      }
      HStack {
        Spacer()
        Button(strings.done, action: onDone)
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding(16)
    .frame(width: 360)
    .onAppear {
      if !store.config.symbols.contains(symbol), let first = store.config.symbols.first {
        symbol = first
      }
    }
    .onChange(of: symbol) { guessDirection() }
    .onChange(of: priceText) { guessDirection() }
  }

  /// The newest price of the symbol chosen.
  private var latest: Double? {
    store.quotes[symbol].map(\.latest).flatMap { $0 > 0 ? $0 : nil }
  }

  /// The name, where the code is a number, and the newest price, to set the alert against.
  private var detail: String {
    var parts: [String] = []
    if let quote = store.quotes[symbol], Format.label(symbol, quote) != Self.editableText(symbol) {
      parts.append(quote.name)
    }
    if let latest {
      parts.append(store.strings.lastPrice(Format.price(latest)))
    }
    return parts.joined(separator: " · ")
  }

  /// The symbol as the settings write it, with its name where the code is a number: 腾讯控股 hk00700.
  private func optionText(_ id: String) -> String {
    let label = Format.label(id, store.quotes[id])
    let text = Self.editableText(id)
    return label == text ? text : "\(label)  \(text)"
  }

  private static func editableText(_ id: String) -> String {
    guard let symbol = StockSymbol(id: id), symbol.market == .us else { return id }
    return symbol.code
  }

  /// Picks rises or falls by which side of the last price the target is; the user can still change it.
  private func guessDirection() {
    guard let target = PriceAlert.parsePrice(priceText), let latest, target != latest else { return }
    below = target < latest
  }

  private func add() {
    guard let price = PriceAlert.parsePrice(priceText) else {
      invalid = true
      return
    }
    invalid = false
    guard store.config.symbols.contains(symbol) else { return }
    let alert = PriceAlert(symbol: symbol, price: price, below: below)
    store.update { config in
      if !config.alerts.contains(alert) {
        config.alerts.append(alert)
      }
    }
    priceText = ""
  }
}
