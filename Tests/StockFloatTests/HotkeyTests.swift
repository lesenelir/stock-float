import AppKit
import Testing

@testable import StockFloat

@Test func readsAShortcut() throws {
  let spec = try #require(HotkeySpec("ctrl+opt+s"))

  #expect(spec.key == "s")
  #expect(spec.modifiers == [.control, .option])
  #expect(spec.display == "⌃⌥S")
}

@Test(arguments: [
  ("Cmd + Shift + 9", "⇧⌘9"),
  ("alt+command+K", "⌥⌘K"),
  ("control+option+shift+cmd+a", "⌃⌥⇧⌘A"),
])
func acceptsSpellingsAndOrdersModifiersLikeAMenu(text: String, display: String) {
  #expect(HotkeySpec(text)?.display == display)
}

// A bare key or Shift alone would swallow ordinary typing.
@Test(arguments: ["", "s", "shift+s", "ctrl+", "ctrl+f13", "ctrl+opt", "hyper+s", "ctrl+ss"])
func rejectsUnusableShortcuts(text: String) {
  #expect(HotkeySpec(text) == nil)
}
