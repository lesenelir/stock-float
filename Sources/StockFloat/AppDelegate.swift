import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store = QuoteStore(config: .load())
  private var panel: FloatingPanel?
  private var settingsWindow: NSWindow?
  private var modifierTimer: Timer?

  private static let positionKey = "panelTopLeft"

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()

    let panel = FloatingPanel(
      rootView: QuoteListView(store: store) { [weak self] size in
        self?.panel?.resize(to: size)
      })
    self.panel = panel
    panel.contextMenu = { [weak self] in self?.makeContextMenu() ?? NSMenu() }
    panel.onUserMove = { topLeft in
      UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.positionKey)
    }
    panel.place(topLeft: UserDefaults.standard.string(forKey: Self.positionKey).map(NSPointFromString))
    panel.orderFrontRegardless()

    applyClickThrough()
    store.start()
  }

  // MARK: Menus

  // An accessory app shows no menu bar, but text fields still need these items for ⌘C / ⌘V / ⌘W to work.
  private func makeMainMenu() -> NSMenu {
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "退出 StockFloat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let editMenu = NSMenu(title: "编辑")
    editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    let mainMenu = NSMenu()
    for submenu in [appMenu, editMenu] {
      let item = NSMenuItem()
      item.submenu = submenu
      mainMenu.addItem(item)
    }
    return mainMenu
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(item("设置…", #selector(openSettings)))
    menu.addItem(.separator())
    menu.addItem(item("绿涨红跌", #selector(useGreenUp), checked: store.config.upColor == .green))
    menu.addItem(item("红涨绿跌", #selector(useRedUp), checked: store.config.upColor == .red))
    menu.addItem(.separator())
    menu.addItem(item("鼠标穿透（按住 ⌥ 临时操作）", #selector(toggleClickThrough), checked: store.config.clickThrough))

    let loginItem = item(
      "开机启动", #selector(toggleLaunchAtLogin), checked: canLaunchAtLogin && SMAppService.mainApp.status == .enabled)
    if !canLaunchAtLogin {
      loginItem.action = nil
      loginItem.toolTip = "需要以打包后的 StockFloat.app 运行"
    }
    menu.addItem(loginItem)

    menu.addItem(.separator())
    menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    return menu
  }

  private func item(_ title: String, _ action: Selector, checked: Bool = false) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.state = checked ? .on : .off
    return item
  }

  // MARK: Actions

  @objc private func openSettings() {
    settingsWindow?.close()
    let view = SettingsView(
      symbolsText: store.config.symbols.map(Self.editableText).joined(separator: "\n"),
      longbridge: store.config.longbridge,
      finnhubKey: store.config.finnhubKey,
      onSave: { [weak self] symbols, longbridge, finnhubKey in
        self?.store.update {
          $0.symbols = symbols
          $0.longbridge = longbridge
          $0.finnhubKey = finnhubKey
        }
        self?.settingsWindow?.close()
      },
      onCancel: { [weak self] in self?.settingsWindow?.close() }
    )
    let window = NSWindow(contentViewController: NSHostingController(rootView: view))
    window.title = "StockFloat 设置"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
    settingsWindow = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  // US symbols are shown without their prefix, the way the settings hint asks for them.
  private static func editableText(_ id: String) -> String {
    guard let symbol = StockSymbol(id: id), symbol.market == .us else { return id }
    return symbol.code
  }

  @objc private func useGreenUp() {
    store.update { $0.upColor = .green }
  }

  @objc private func useRedUp() {
    store.update { $0.upColor = .red }
  }

  @objc private func toggleClickThrough() {
    store.update { $0.clickThrough.toggle() }
    applyClickThrough()
  }

  // Polling the modifier state needs no Accessibility permission, unlike a global event monitor.
  private func applyClickThrough() {
    modifierTimer?.invalidate()
    modifierTimer = nil
    panel?.ignoresMouseEvents = store.config.clickThrough
    guard store.config.clickThrough else { return }
    modifierTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.panel?.ignoresMouseEvents = !NSEvent.modifierFlags.contains(.option)
      }
    }
  }

  private var canLaunchAtLogin: Bool {
    Bundle.main.bundleURL.pathExtension == "app"
  }

  @objc private func toggleLaunchAtLogin() {
    do {
      if SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
    } catch {
      NSApp.activate()
      NSAlert(error: error).runModal()
    }
  }
}
