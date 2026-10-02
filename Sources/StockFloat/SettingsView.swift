import SwiftUI

struct SettingsView: View {
  let strings: Strings
  @State var symbolsText: String
  @State var longbridge: Bool
  @State var finnhubKey: String
  let onSave: (_ symbols: [String], _ longbridge: Bool, _ finnhubKey: String) -> Void
  let onCancel: () -> Void

  @State private var invalid: [String] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(strings.symbolsLabel)
        TextEditor(text: $symbolsText)
          .font(.system(size: 13, design: .monospaced))
          .frame(height: 140)
          .border(.separator)
        Text(strings.symbolsHint)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if !invalid.isEmpty {
          Text(strings.unrecognized(invalid))
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Toggle(strings.longbridgeToggle, isOn: $longbridge)
        Text(strings.longbridgeHint)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(strings.finnhubKey)
        TextField(strings.finnhubPlaceholder, text: $finnhubKey)
          .textFieldStyle(.roundedBorder)
          .disabled(longbridge)
      }
      HStack {
        Spacer()
        Button(strings.cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(strings.save, action: save)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(width: 360)
  }

  private func save() {
    let entries = symbolsText.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" }).map(String.init)
    let parsed = Config.parseSymbols(entries)
    invalid = parsed.invalid
    guard invalid.isEmpty else { return }
    onSave(parsed.ids, longbridge, finnhubKey.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
