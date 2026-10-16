import AppKit
import UserNotifications

/// Shows a system notification for each price alert that goes off.
@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
  /// Set once the user has been told that alerts cannot notify them.
  private var warnedDenied = false

  /// Notifications need the app bundle; `swift run` has none, and the notification center throws without one.
  private var isAvailable: Bool {
    Bundle.main.bundleURL.pathExtension == "app"
  }

  func start() {
    guard isAvailable else { return }
    UNUserNotificationCenter.current().delegate = self
  }

  /// Notify of the alerts `quote` set off. The first time, macOS asks whether the app may notify.
  func notify(_ quote: Quote, _ hits: [PriceAlert], strings: Strings) {
    guard isAvailable else { return }
    let name = Format.label(quote.symbol, quote)
    let body = strings.alertBody(
      session: quote.extended?.session, Format.price(quote.latest),
      Format.percent(quote.extended?.changePercent ?? quote.changePercent))
    let requests = hits.map { hit in
      let content = UNMutableNotificationContent()
      content.title = strings.alertTitle(name, below: hit.below, Format.price(hit.price))
      content.body = body
      content.sound = .default
      content.threadIdentifier = "price-alerts"
      return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }
    Task {
      let center = UNUserNotificationCenter.current()
      let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
      guard allowed else {
        warnDenied(strings)
        return
      }
      for request in requests {
        try? await center.add(request)
      }
    }
  }

  /// An alert the user set went unseen: say so, once a run.
  private func warnDenied(_ strings: Strings) {
    guard !warnedDenied else { return }
    warnedDenied = true
    let alert = NSAlert()
    alert.messageText = strings.notificationsOff
    alert.informativeText = strings.notificationsOffDetail
    NSApp.activate()
    alert.runModal()
  }

  // Show banners even while the app is in front, as it is when its settings are open.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}
