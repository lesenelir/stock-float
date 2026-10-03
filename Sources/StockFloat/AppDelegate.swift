import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let store = QuoteStore(config: .load())
  private var panel: FloatingPanel?
  private var statusItem: NSStatusItem?
  private var settingsWindow: NSWindow?
  private var modifierTimer: Timer?
  private var hotkey: GlobalHotkey?

  private static let positionKey = "panelTopLeft"

  func applicationDidFinishLaunching(_ notification: Notification) {
    // The bundle is marked as a background app so a user who turned the Dock icon off never sees it flash.
    NSApp.setActivationPolicy(store.config.dockIcon ? .regular : .accessory)
    NSApp.mainMenu = makeMainMenu()

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "StockFloat")
    let statusMenu = NSMenu()
    statusMenu.delegate = self
    statusItem.menu = statusMenu
    self.statusItem = statusItem

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
    panel.alphaValue = store.config.opacity
    panel.orderFrontRegardless()

    applyClickThrough()
    registerHotkey()
    store.start()
  }

  // Opening the app again, from the Dock, Spotlight or Finder, brings a hidden panel back.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    panel?.orderFrontRegardless()
    return false
  }

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()
    menu.addItem(item(store.strings.settings, #selector(openSettings)))
    menu.addItem(panelItem())
    return menu
  }

  /// The menu bar icon's menu is rebuilt each time it opens, so its check marks are current.
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    populate(menu)
  }

  // MARK: Menus

  // Shown when the app is active; without the Dock icon it is never visible, but text fields still need the
  // Edit items for ⌘C / ⌘V / ⌘W to work.
  private func makeMainMenu() -> NSMenu {
    let strings = store.strings
    let appMenu = NSMenu()
    appMenu.addItem(item(strings.settings, #selector(openSettings)))
    appMenu.addItem(item(strings.showPanel, #selector(showPanel)))
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: strings.quitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let editMenu = NSMenu(title: strings.edit)
    editMenu.addItem(withTitle: strings.undo, action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: strings.redo, action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: strings.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: strings.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: strings.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: strings.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: strings.closeWindow, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

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
    populate(menu)
    return menu
  }

  /// The one menu behind the panel's right-click and the menu bar icon.
  // Grouped by kind: the two everyday actions, the two submenus, then the three behaviour toggles by how often
  // they change.
  private func populate(_ menu: NSMenu) {
    let strings = store.strings
    menu.addItem(item(strings.settings, #selector(openSettings)))
    menu.addItem(panelItem())
    menu.addItem(.separator())

    let appearanceMenu = NSMenu()
    appearanceMenu.addItem(.sectionHeader(title: strings.colors))
    for color in Config.UpColor.allCases {
      appearanceMenu.addItem(
        choice(strings.name(of: color), #selector(selectColor(_:)), color.rawValue, store.config.upColor == color))
    }
    appearanceMenu.addItem(.sectionHeader(title: strings.textSize))
    for size in Config.TextSize.allCases {
      appearanceMenu.addItem(
        choice(strings.name(of: size), #selector(selectTextSize(_:)), size.rawValue, store.config.textSize == size))
    }
    appearanceMenu.addItem(.sectionHeader(title: strings.opacity))
    for opacity in Config.opacityChoices {
      appearanceMenu.addItem(
        choice(
          "\(Int((opacity * 100).rounded()))%", #selector(selectOpacity(_:)), opacity,
          store.config.opacity == opacity))
    }
    let appearanceItem = NSMenuItem(title: strings.appearance, action: nil, keyEquivalent: "")
    appearanceItem.submenu = appearanceMenu
    menu.addItem(appearanceItem)

    let languageMenu = NSMenu()
    for setting in LanguageSetting.allCases {
      languageMenu.addItem(
        choice(
          strings.name(of: setting), #selector(selectLanguage(_:)), setting.rawValue,
          store.config.language == setting))
    }
    let languageItem = NSMenuItem(title: strings.languageMenu, action: nil, keyEquivalent: "")
    languageItem.submenu = languageMenu
    menu.addItem(languageItem)
    menu.addItem(.separator())

    menu.addItem(item(strings.clickThrough, #selector(toggleClickThrough), checked: store.config.clickThrough))
    menu.addItem(item(strings.dockIcon, #selector(toggleDockIcon), checked: store.config.dockIcon))
    let loginItem = item(
      strings.launchAtLogin, #selector(toggleLaunchAtLogin),
      checked: canLaunchAtLogin && SMAppService.mainApp.status == .enabled)
    if !canLaunchAtLogin {
      loginItem.action = nil
      loginItem.toolTip = strings.launchAtLoginUnavailable
    }
    menu.addItem(loginItem)
    menu.addItem(.separator())

    menu.addItem(withTitle: strings.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
  }

  /// "Show Panel" or "Hide Panel", whichever applies now, with the shortcut shown only when it is registered.
  private func panelItem() -> NSMenuItem {
    let visible = panel?.isVisible == true
    let item = item(visible ? store.strings.hidePanel : store.strings.showPanel, #selector(togglePanel))
    if hotkey != nil, let spec = HotkeySpec(store.config.hotkey) {
      item.keyEquivalent = spec.key
      item.keyEquivalentModifierMask = spec.modifiers
    }
    return item
  }

  private func item(_ title: String, _ action: Selector, checked: Bool = false) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.state = checked ? .on : .off
    return item
  }

  /// One option of a pick-one group; `value` comes back to the action as `representedObject`.
  private func choice(_ title: String, _ action: Selector, _ value: Any, _ selected: Bool) -> NSMenuItem {
    let item = item(title, action, checked: selected)
    item.representedObject = value
    return item
  }

  // MARK: Actions

  @objc private func openSettings() {
    settingsWindow?.close()
    let view = SettingsView(
      strings: store.strings,
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
    window.title = store.strings.settingsTitle
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

  @objc private func togglePanel() {
    guard let panel else { return }
    if panel.isVisible {
      panel.orderOut(nil)
    } else {
      panel.orderFrontRegardless()
    }
  }

  @objc private func showPanel() {
    panel?.orderFrontRegardless()
  }

  @objc private func toggleDockIcon() {
    store.update { $0.dockIcon.toggle() }
    NSApp.setActivationPolicy(store.config.dockIcon ? .regular : .accessory)
  }

  private func registerHotkey() {
    hotkey?.unregister()
    hotkey = HotkeySpec(store.config.hotkey).flatMap { spec in
      GlobalHotkey(spec) { [weak self] in self?.togglePanel() }
    }
  }

  @objc private func selectColor(_ sender: NSMenuItem) {
    guard let color = (sender.representedObject as? String).flatMap(Config.UpColor.init(rawValue:)) else { return }
    store.update { $0.upColor = color }
  }

  @objc private func selectTextSize(_ sender: NSMenuItem) {
    guard let size = (sender.representedObject as? String).flatMap(Config.TextSize.init(rawValue:)) else { return }
    store.update { $0.textSize = size }
  }

  @objc private func selectOpacity(_ sender: NSMenuItem) {
    guard let opacity = sender.representedObject as? Double else { return }
    store.update { $0.opacity = opacity }
    panel?.alphaValue = opacity
  }

  @objc private func selectLanguage(_ sender: NSMenuItem) {
    guard let rawValue = sender.representedObject as? String, let setting = LanguageSetting(rawValue: rawValue)
    else { return }
    store.update { $0.language = setting }
    // The panel follows the store on its own; the main menu and an open settings window were built once.
    NSApp.mainMenu = makeMainMenu()
    settingsWindow?.close()
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
