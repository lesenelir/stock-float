import SwiftUI

struct SettingsView: View {
  @State var symbolsText: String
  @State var longbridge: Bool
  @State var finnhubKey: String
  let onSave: (_ symbols: [String], _ longbridge: Bool, _ finnhubKey: String) -> Void
  let onCancel: () -> Void

  @State private var invalid: [String] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("标的（每行一个）")
        TextEditor(text: $symbolsText)
          .font(.system(size: 13, design: .monospaced))
          .frame(height: 140)
          .border(.separator)
        Text("美股直接写代码，如 AAPL；港股 hk00700；A 股 sh600519、sz000001")
          .font(.caption)
          .foregroundStyle(.secondary)
        if !invalid.isEmpty {
          Text("无法识别：\(invalid.joined(separator: "、"))")
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Toggle("美股使用长桥行情（含盘前、盘后、夜盘）", isOn: $longbridge)
        Text("需先安装长桥 CLI，并在终端运行 longbridge auth login")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("Finnhub API key")
        TextField("留空则美股使用腾讯行情（约 20 秒一次快照）", text: $finnhubKey)
          .textFieldStyle(.roundedBorder)
          .disabled(longbridge)
      }
      HStack {
        Spacer()
        Button("取消", action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button("保存", action: save)
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
