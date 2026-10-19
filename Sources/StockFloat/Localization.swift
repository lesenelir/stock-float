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

  func updateHint(_ version: String) -> String {
    t("新版本 \(version) 可用，右键更新", "Version \(version) available. Right-click to update.")
  }

  // MARK: Context menu

  func updateTo(_ version: String) -> String { t("更新到 \(version)", "Update to \(version)") }
  var updating: String { t("正在下载更新…", "Downloading Update…") }
  var updateFailed: String { t("更新失败", "Update Failed") }
  var openDownloadPage: String { t("打开下载页面", "Open Download Page") }
  var settings: String { t("设置…", "Settings…") }
  var hidePanel: String { t("隐藏小窗", "Hide Panel") }
  var showPanel: String { t("显示小窗", "Show Panel") }
  var dockIcon: String { t("在 Dock 中显示图标", "Show in Dock") }
  var appearance: String { t("外观", "Appearance") }
  var colors: String { t("配色", "Colors") }
  var textSize: String { t("字号", "Text Size") }
  var opacity: String { t("不透明度", "Opacity") }
  var flash: String { t("价格变动时闪烁", "Flash on price change") }

  func name(of color: Config.UpColor) -> String {
    switch color {
    case .green: t("绿涨红跌", "Green up, red down")
    case .red: t("红涨绿跌", "Red up, green down")
    case .mono: t("不着色", "No color")
    }
  }

  var green: String { t("绿色", "Green") }
  var red: String { t("红色", "Red") }

  /// A shade of green or red, named as Tailwind CSS names it, such as green-500.
  func name(of shade: Config.Shade, in color: String) -> String {
    shade == .system ? t("系统默认", "System") : "\(color)-\(shade.rawValue)"
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

  // MARK: Price alerts

  var priceAlerts: String { t("到价提醒…", "Price Alerts…") }
  var alertsTitle: String { t("到价提醒", "Price Alerts") }
  var alertSymbol: String { t("标的", "Symbol") }
  var alertPrice: String { t("目标价", "Target price") }
  var alertDirection: String { t("方向", "Direction") }
  var alertRises: String { t("涨到", "Rises to") }
  var alertFalls: String { t("跌到", "Falls to") }
  var addAlert: String { t("添加", "Add") }
  var removeAlert: String { t("删除", "Remove") }
  var done: String { t("完成", "Done") }
  var invalidPrice: String { t("请输入大于 0 的价格", "Enter a price above 0.") }
  var alertsNeedSymbols: String { t("请先在设置中添加标的", "Add symbols in Settings first.") }
  var noAlerts: String {
    t("暂无提醒。到价时会在系统通知中提醒一次。", "No alerts. Each one notifies you once, in Notification Center.")
  }

  /// The latest price of the symbol an alert is being set for.
  func lastPrice(_ price: String) -> String { t("现价 \(price)", "Last \(price)") }

  /// When an alert goes off, such as "Rises to 200.00".
  func alertCondition(below: Bool, _ price: String) -> String {
    "\(below ? alertFalls : alertRises) \(price)"
  }

  /// The notification of an alert going off, such as "AAPL rose to 200.00".
  func alertTitle(_ label: String, below: Bool, _ price: String) -> String {
    below ? t("\(label) 跌到 \(price)", "\(label) fell to \(price)") : t("\(label) 涨到 \(price)", "\(label) rose to \(price)")
  }

  /// The price that set an alert off and its change, such as "Now 201.30 (+2.15%)"; `session` names the extended
  /// session it traded in.
  func alertBody(session: ExtendedQuote.Session?, _ price: String, _ change: String) -> String {
    let when = session.map(self.session) ?? t("现价", "Now")
    return t("\(when) \(price)（\(change)）", "\(when) \(price) (\(change))")
  }

  var notificationsOff: String { t("到价提醒无法通知", "Price Alerts Can't Notify You") }
  var notificationsOffDetail: String {
    t("请在“系统设置 › 通知”中允许 StockFloat 发送通知。", "Allow StockFloat to send notifications in System Settings › Notifications.")
  }
}
