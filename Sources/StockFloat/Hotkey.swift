import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut written like `ctrl+opt+s`: modifiers, then one letter or digit.
struct HotkeySpec: Equatable {
  /// The letter or digit, lowercased.
  let key: String
  let modifiers: NSEvent.ModifierFlags

  // A shortcut needs Control, Option or Command, so it cannot shadow ordinary typing.
  init?(_ text: String) {
    var parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let key = parts.popLast(), Self.keyCodes[key] != nil else { return nil }
    var modifiers: NSEvent.ModifierFlags = []
    for part in parts {
      switch part {
      case "ctrl", "control": modifiers.insert(.control)
      case "opt", "option", "alt": modifiers.insert(.option)
      case "cmd", "command": modifiers.insert(.command)
      case "shift": modifiers.insert(.shift)
      default: return nil
      }
    }
    guard !modifiers.isDisjoint(with: [.control, .option, .command]) else { return nil }
    self.key = key
    self.modifiers = modifiers
  }

  /// The shortcut in menu notation, such as `⌃⌥S`.
  var display: String {
    let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
    return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.uppercased()
  }

  fileprivate var keyCode: UInt32 {
    UInt32(Self.keyCodes[key] ?? 0)
  }

  fileprivate var carbonModifiers: UInt32 {
    let flags: [(NSEvent.ModifierFlags, Int)] = [
      (.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey),
    ]
    return flags.filter { modifiers.contains($0.0) }.reduce(0) { $0 | UInt32($1.1) }
  }

  // Virtual key codes are positions on an ANSI keyboard, not characters, so they are listed, not computed.
  private static let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
    "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
    "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
    "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
  ]
}

/// A system-wide shortcut. Carbon hot keys work from any app and need no Accessibility permission.
@MainActor
final class GlobalHotkey {
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let action: () -> Void

  /// Fails when the system refuses the registration.
  init?(_ spec: HotkeySpec, action: @escaping () -> Void) {
    self.action = action

    var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installed = InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        // Carbon delivers hot key events on the main thread.
        MainActor.assumeIsolated {
          Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue().action()
        }
        return noErr
      },
      1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
    guard installed == noErr else { return nil }

    // "SFHK": any four-character tag that identifies this app's hot keys.
    let id = EventHotKeyID(signature: 0x5346_484B, id: 1)
    let registered = RegisterEventHotKey(
      spec.keyCode, spec.carbonModifiers, id, GetEventDispatcherTarget(), 0, &hotKey)
    guard registered == noErr else {
      unregister()
      return nil
    }
  }

  /// Release the shortcut; call this before dropping the object, which the handler points at.
  func unregister() {
    if let hotKey {
      UnregisterEventHotKey(hotKey)
    }
    if let handler {
      RemoveEventHandler(handler)
    }
    hotKey = nil
    handler = nil
  }
}
