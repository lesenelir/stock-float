import SwiftUI

struct QuoteListView: View {
  let store: QuoteStore
  /// Reports the content size so the panel can resize around it.
  let onResize: (CGSize) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(store.config.symbols, id: \.self) { symbol in
        QuoteRow(symbol: symbol, quote: store.quotes[symbol], upColor: store.config.upColor)
      }
      if store.config.symbols.isEmpty {
        Text("右键添加标的")
          .foregroundStyle(.secondary)
      }
      if !store.offlineSources.isEmpty {
        Text("连接中断，价格可能已过期")
          .font(.system(size: 10))
          .foregroundStyle(.orange)
          .padding(.horizontal, 4)
      }
    }
    .font(.system(size: 12, weight: .medium))
    .padding(6)
    .frame(width: 204)
    .fixedSize()
    .onGeometryChange(for: CGSize.self) { $0.size } action: { onResize($0) }
  }
}

private struct QuoteRow: View {
  let symbol: String
  let quote: Quote?
  let upColor: Config.UpColor

  @State private var flashColor = Color.clear
  @State private var flashCount = 0

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(priceText)
        .monospacedDigit()
      Text(percentText)
        .monospacedDigit()
        .foregroundStyle(color(for: quote?.changePercent ?? 0))
        .frame(width: 56, alignment: .trailing)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .background {
      RoundedRectangle(cornerRadius: 4)
        .fill(flashColor)
        .phaseAnimator([0.0, 0.3], trigger: flashCount) { shape, opacity in
          shape.opacity(opacity)
        } animation: { opacity in
          opacity > 0 ? .easeOut(duration: 0.1) : .easeOut(duration: 0.6)
        }
    }
    .onChange(of: quote?.price) { old, new in
      guard let old, let new, old != new else { return }
      flashColor = color(for: new - old)
      flashCount += 1
    }
  }

  // US tickers are already short; other markets read better by name.
  private var label: String {
    guard let parsed = StockSymbol(id: symbol) else { return symbol }
    if parsed.market == .us {
      return parsed.code
    }
    return quote?.name ?? parsed.code
  }

  private var priceText: String {
    guard let quote else { return "—" }
    return String(format: quote.price < 1 ? "%.3f" : "%.2f", quote.price)
  }

  private var percentText: String {
    guard let quote else { return "—" }
    return String(format: "%+.2f%%", quote.changePercent)
  }

  private func color(for change: Double) -> Color {
    if change == 0 {
      return .secondary
    }
    return (change > 0) == (upColor == .green) ? .green : .red
  }
}
