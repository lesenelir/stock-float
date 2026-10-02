import AppKit
import SwiftUI

/// Borderless panel that floats above every Space, including other apps' full-screen ones, without taking focus.
final class FloatingPanel: NSPanel {
  /// Builds the menu shown on right-click.
  var contextMenu: (() -> NSMenu)?
  /// Called with the new top-left corner after the user drags the panel.
  var onUserMove: ((NSPoint) -> Void)?

  private static let screenMargin: CGFloat = 8

  private var topLeft: NSPoint { NSPoint(x: frame.minX, y: frame.maxY) }
  private var savedTopLeft: NSPoint?
  // Placement waits for the first content size, since the default position depends on the panel's width.
  private var isPlaced = false
  // Where the panel was last put; a move away from it can only be the user dragging.
  private var placedTopLeft = NSPoint.zero

  init(rootView: some View) {
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    animationBehavior = .none

    // An explicit effect view stays vivid while the panel is inactive, which it always is.
    let background = NSVisualEffectView()
    background.material = .hudWindow
    background.blendingMode = .behindWindow
    background.state = .active
    // A layer corner radius does not clip the behind-window material, which leaves square corners showing.
    background.maskImage = Self.roundedMask(radius: 10)

    let hosting = NSHostingView(rootView: rootView)
    hosting.sizingOptions = []
    hosting.frame = background.bounds
    hosting.autoresizingMask = [.width, .height]
    background.addSubview(hosting)
    contentView = background

    NotificationCenter.default.addObserver(
      self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: self)
  }

  /// A rounded rectangle that stretches to any size while keeping its corners.
  private static func roundedMask(radius: CGFloat) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
  }

  /// Resize around the content, keeping the top-left corner where it is.
  func resize(to size: CGSize) {
    guard size.width > 0, size.height > 0, size != frame.size else { return }
    setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    invalidateShadow()
    placeIfSized()
  }

  /// Put the panel at `topLeft`, or in the main screen's top-right corner when it would not fit on any screen there.
  func place(topLeft: NSPoint?) {
    savedTopLeft = topLeft
    isPlaced = false
    placeIfSized()
  }

  private func placeIfSized() {
    guard !isPlaced, frame.width > 0 else { return }
    let target: NSPoint
    if let savedTopLeft, fitsOnScreen(at: savedTopLeft) {
      target = savedTopLeft
    } else if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
      target = NSPoint(x: visible.maxX - frame.width - Self.screenMargin, y: visible.maxY - Self.screenMargin)
    } else {
      return
    }
    isPlaced = true
    placedTopLeft = target
    setFrameTopLeftPoint(target)
  }

  private func fitsOnScreen(at topLeft: NSPoint) -> Bool {
    let target = NSRect(x: topLeft.x, y: topLeft.y - frame.height, width: frame.width, height: frame.height)
    return NSScreen.screens.contains { $0.frame.contains(target) }
  }

  @objc private func didMove() {
    let current = topLeft
    guard isPlaced, abs(current.x - placedTopLeft.x) > 0.5 || abs(current.y - placedTopLeft.y) > 0.5 else { return }
    placedTopLeft = current
    onUserMove?(current)
  }

  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .rightMouseDown:
      if let menu = contextMenu?(), let contentView {
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
      }
    case .leftMouseDown:
      performDrag(with: event)
    default:
      super.sendEvent(event)
    }
  }
}
