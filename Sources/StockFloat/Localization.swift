import Foundation

enum Language: String, Sendable {
  case zh, en
}

/// The user's language choice; `system` follows the first preferred language of macOS.
enum LanguageSetting: String, Codable, CaseIterable, Sendable {
  case system, zh, en

  func resolved(preferred: [String] = Locale.preferredLanguages) -> Language {
    switch self {
    case .zh: .zh
    case .en: .en
    case .system: preferred.first?.hasPrefix("zh") == true ? .zh : .en
    }
  }
}

/// Every user-facing string, in one language.
struct Strings: Equatable, Sendable {
  let language: Language

  private func t(_ zh: String, _ en: String) -> String {
    language == .zh ? zh : en
  }

  // MARK: Panel

  var emptyHint: String { t("右键添加标的", "Right-click to add symbols") }

  // Kept short: the label shares a 204pt row with a price and a percentage.
  func session(_ session: ExtendedQuote.Session) -> String {
    switch session {
    case .pre: t("盘前", "Pre")
    case .post: t("盘后", "Post")
    case .overnight: t("夜盘", "Night")
    }
  }

  func outage(_ outage: Outage) -> String {
    switch outage {
    case .unreachable:
      t("连接中断，价格可能已过期", "Disconnected. Prices may be stale.")
    case .longbridgeMissing:
      t("未找到 longbridge 命令，请先安装长桥 CLI", "longbridge command not found. Install the Longbridge CLI.")
    case .longbridgeLoggedOut:
      t("长桥未登录，请在终端运行 longbridge auth login", "Not logged in to Longbridge. Run longbridge auth login in a terminal.")
    case .longbridge(let detail):
      t("长桥：\(detail)", "Longbridge: \(detail)")
    }
  }

  // MARK: Context menu

  var settings: String { t("设置…", "Settings…") }
  var hidePanel: String { t("隐藏小窗", "Hide Panel") }
  var showPanel: String { t("显示小窗", "Show Panel") }
  var dockIcon: String { t("在 Dock 中显示图标", "Show in Dock") }
  var appearance: String { t("外观", "Appearance") }
  var colors: String { t("配色", "Colors") }
  var textSize: String { t("字号", "Text Size") }
  var opacity: String { t("不透明度", "Opacity") }

  func name(of color: Config.UpColor) -> String {
    switch color {
    case .green: t("绿涨红跌", "Green up, red down")
    case .red: t("红涨绿跌", "Red up, green down")
    case .mono: t("不着色", "No color")
    }
  }

  func name(of size: Config.TextSize) -> String {
    switch size {
    case .small: t("小", "Small")
    case .medium: t("中", "Medium")
    case .large: t("大", "Large")
    }
  }
  var clickThrough: String { t("鼠标穿透（按住 ⌥ 临时操作）", "Click-through (hold ⌥ to interact)") }
  var launchAtLogin: String { t("开机启动", "Launch at login") }
  var launchAtLoginUnavailable: String { t("需要以打包后的 StockFloat.app 运行", "Requires running the bundled StockFloat.app") }
  var languageMenu: String { t("语言", "Language") }
  var quit: String { t("退出", "Quit") }

  /// Each language is named in itself, so it can be found from the other one.
  func name(of setting: LanguageSetting) -> String {
    switch setting {
    case .system: t("跟随系统", "System")
    case .zh: "中文"
    case .en: "English"
    }
  }

  // MARK: Main menu

  var quitApp: String { t("退出 StockFloat", "Quit StockFloat") }
  var edit: String { t("编辑", "Edit") }
  var undo: String { t("撤销", "Undo") }
  var redo: String { t("重做", "Redo") }
  var cut: String { t("剪切", "Cut") }
  var copy: String { t("拷贝", "Copy") }
  var paste: String { t("粘贴", "Paste") }
  var selectAll: String { t("全选", "Select All") }
  var closeWindow: String { t("关闭窗口", "Close Window") }

  // MARK: Settings

  var settingsTitle: String { t("StockFloat 设置", "StockFloat Settings") }
  var symbolsLabel: String { t("标的（每行一个）", "Symbols (one per line)") }
  var symbolsHint: String {
    t(
      "美股直接写代码，如 AAPL；港股 hk00700；A 股 sh600519、sz000001",
      "US: the ticker, e.g. AAPL. Hong Kong: hk00700. A-shares: sh600519, sz000001.")
  }
  var longbridgeToggle: String {
    t("美股使用长桥行情（含盘前、盘后、夜盘）", "Use Longbridge for US quotes (adds pre-market, post-market, overnight)")
  }
  var longbridgeHint: String {
    t("需先安装长桥 CLI，并在终端运行 longbridge auth login", "Install the Longbridge CLI and run longbridge auth login first.")
  }
  var finnhubKey: String { "Finnhub API key" }
  var finnhubPlaceholder: String {
    t("留空则美股使用腾讯行情（约 20 秒一次快照）", "Empty: Tencent quotes, about every 20 s")
  }
  var cancel: String { t("取消", "Cancel") }
  var save: String { t("保存", "Save") }

  func unrecognized(_ entries: [String]) -> String {
    t("无法识别：\(entries.joined(separator: "、"))", "Not recognized: \(entries.joined(separator: ", "))")
  }
}
