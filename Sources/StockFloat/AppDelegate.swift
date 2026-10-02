import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store = QuoteStore(config: .load())
  private var panel: FloatingPanel?
  private var settingsWindow: NSWindow?
  private var modifierTimer: Timer?
  private var hotkey: GlobalHotkey?

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
    panel.alphaValue = store.config.opacity
    panel.orderFrontRegardless()

    applyClickThrough()
    registerHotkey()
    store.start()
  }

  // With no Dock or menu bar item, opening the app again is the way back to a hidden panel.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    panel?.orderFrontRegardless()
    return false
  }

  // MARK: Menus

  // An accessory app shows no menu bar, but text fields still need these items for ⌘C / ⌘V / ⌘W to work.
  private func makeMainMenu() -> NSMenu {
    let strings = store.strings
    let appMenu = NSMenu()
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
    let strings = store.strings
    let menu = NSMenu()
    menu.addItem(item(strings.settings, #selector(openSettings)))
    let hideItem = item(strings.hidePanel, #selector(togglePanel))
    // Shown only when the shortcut is actually registered, so the menu never advertises a dead key.
    if hotkey != nil, let spec = HotkeySpec(store.config.hotkey) {
      hideItem.keyEquivalent = spec.key
      hideItem.keyEquivalentModifierMask = spec.modifiers
    }
    menu.addItem(hideItem)
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

    menu.addItem(item(strings.clickThrough, #selector(toggleClickThrough), checked: store.config.clickThrough))

    let loginItem = item(
      strings.launchAtLogin, #selector(toggleLaunchAtLogin),
      checked: canLaunchAtLogin && SMAppService.mainApp.status == .enabled)
    if !canLaunchAtLogin {
      loginItem.action = nil
      loginItem.toolTip = strings.launchAtLoginUnavailable
    }
    menu.addItem(loginItem)

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
    menu.addItem(withTitle: strings.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    return menu
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
