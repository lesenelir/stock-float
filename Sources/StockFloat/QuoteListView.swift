import SwiftUI

struct QuoteListView: View {
  let store: QuoteStore
  let updater: Updater
  /// Reports the content size so the panel can resize around it.
  let onResize: (CGSize) -> Void

  var body: some View {
    let scale = store.config.textSize.scale
    // Re-evaluated every minute, so a price that stops updating fades without new data arriving.
    TimelineView(.periodic(from: .now, by: 60)) { timeline in
      VStack(alignment: .leading, spacing: 2) {
        ForEach(store.config.symbols, id: \.self) { symbol in
          let quote = store.quotes[symbol]
          QuoteRow(symbol: symbol, quote: quote, upColor: store.config.upColor, strings: store.strings, scale: scale)
            .opacity(quote?.isStale(at: timeline.date) == true ? 0.45 : 1)
        }
        if store.config.symbols.isEmpty {
          Text(store.strings.emptyHint)
            .foregroundStyle(.secondary)
        }
        ForEach(outageMessages, id: \.self) { message in
          Text(message)
            .font(.system(size: 10 * scale))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
        // Quiet on purpose: the panel is on screen all day.
        if let release = updater.available {
          Text(store.strings.updateHint(release.versionText))
            .font(.system(size: 10 * scale))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
      }
      .font(.system(size: 12 * scale, weight: .medium))
      .padding(6)
      .frame(width: 204 * scale)
      .fixedSize()
      .onGeometryChange(for: CGSize.self) { $0.size } action: { onResize($0) }
    }
  }

  private var outageMessages: [String] {
    Set(store.offlineSources.values.map(store.strings.outage)).sorted()
  }
}

private struct QuoteRow: View {
  let symbol: String
  let quote: Quote?
  let upColor: Config.UpColor
  let strings: Strings
  let scale: Double

  @State private var flashColor = Color.clear
  @State private var flashCount = 0

  var body: some View {
    // The name sits on the first line; the extended-hours line hangs under the price column only.
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 1) {
        HStack(spacing: 8) {
          Text(quote.map { priceText($0.price) } ?? "—")
            .monospacedDigit()
          Text(quote.map { percentText($0.changePercent) } ?? "—")
            .monospacedDigit()
            .foregroundStyle(tint(for: quote?.changePercent ?? 0, otherwise: .primary))
            .frame(width: 56 * scale, alignment: .trailing)
        }
        if let extended = quote?.extended {
          HStack(spacing: 8) {
            // The icon hugs the price it labels.
            HStack(spacing: 3) {
              Image(systemName: extended.session.symbolName)
                // A little smaller than the digits: a label, not a third number.
                .font(.system(size: 8.5 * scale))
                .accessibilityLabel(strings.session(extended.session))
              Text(priceText(extended.price))
                .monospacedDigit()
            }
            Text(percentText(extended.changePercent))
              .monospacedDigit()
              .foregroundStyle(tint(for: extended.changePercent, otherwise: .secondary))
              .frame(width: 56 * scale, alignment: .trailing)
          }
          .font(.system(size: 10 * scale, weight: .medium))
          .foregroundStyle(.secondary)
        }
      }
      // Prices never wrap; the name is what gives way when the panel is tight.
      .fixedSize()
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
    // Only regular-session moves flash; extended-hours ticks update quietly.
    .onChange(of: quote?.price) { old, new in
      guard quote?.extended == nil, let old, let new, old != new else { return }
      flashColor = tint(for: new - old, otherwise: .gray)
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

  private func priceText(_ price: Double) -> String {
    String(format: price < 1 ? "%.3f" : "%.2f", price)
  }

  private func percentText(_ percent: Double) -> String {
    String(format: "%+.2f%%", percent)
  }

  /// The gain or loss colour, or `plain` when the colour scheme is monochrome.
  private func tint(for change: Double, otherwise plain: Color) -> Color {
    if upColor == .mono {
      return plain
    }
    if change == 0 {
      return .secondary
    }
    return (change > 0) == (upColor == .green) ? .green : .red
  }
}

