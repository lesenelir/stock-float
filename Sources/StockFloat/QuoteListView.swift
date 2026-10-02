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
      ForEach(outageMessages, id: \.self) { message in
        Text(message)
          .font(.system(size: 10))
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 4)
      }
    }
    .font(.system(size: 12, weight: .medium))
    .padding(6)
    .frame(width: 204)
    .fixedSize()
    .onGeometryChange(for: CGSize.self) { $0.size } action: { onResize($0) }
  }

  private var outageMessages: [String] {
    Set(store.offlineSources.values.map { $0.isEmpty ? "连接中断，价格可能已过期" : $0 }).sorted()
  }
}

private struct QuoteRow: View {
  let symbol: String
  let quote: Quote?
  let upColor: Config.UpColor

  @State private var flashColor = Color.clear
  @State private var flashCount = 0

  var body: some View {
    VStack(spacing: 1) {
      HStack(spacing: 8) {
        Text(label)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(quote.map { priceText($0.price) } ?? "—")
          .monospacedDigit()
        Text(quote.map { percentText($0.changePercent) } ?? "—")
          .monospacedDigit()
          .foregroundStyle(color(for: quote?.changePercent ?? 0))
          .frame(width: 56, alignment: .trailing)
      }
      if let extended = quote?.extended {
        HStack(spacing: 8) {
          Text(sessionLabel(extended.session))
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(priceText(extended.price))
            .monospacedDigit()
          Text(percentText(extended.changePercent))
            .monospacedDigit()
            .foregroundStyle(color(for: extended.changePercent))
            .frame(width: 56, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
      }
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
    .onChange(of: quote?.extended?.price ?? quote?.price) { old, new in
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

  private func sessionLabel(_ session: ExtendedQuote.Session) -> String {
    switch session {
    case .pre: "盘前"
    case .post: "盘后"
    case .overnight: "夜盘"
    }
  }

  private func priceText(_ price: Double) -> String {
    String(format: price < 1 ? "%.3f" : "%.2f", price)
  }

  private func percentText(_ percent: Double) -> String {
    String(format: "%+.2f%%", percent)
  }

  private func color(for change: Double) -> Color {
    if change == 0 {
      return .secondary
    }
    return (change > 0) == (upColor == .green) ? .green : .red
  }
}
