import AppKit
import Foundation
import Observation

/// A dotted numeric version such as `0.2.4`; a leading `v`, as in a tag, is allowed.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
  let parts: [Int]

  init?(_ text: String) {
    let pieces = (text.hasPrefix("v") ? text.dropFirst() : Substring(text)).split(
      separator: ".", omittingEmptySubsequences: false)
    let parts = pieces.compactMap { Int($0) }
    guard !parts.isEmpty, parts.count == pieces.count, parts.allSatisfy({ $0 >= 0 }) else { return nil }
    self.parts = parts
  }

  var description: String {
    parts.map(String.init).joined(separator: ".")
  }

  // Missing parts count as zero, so 0.2 and 0.2.0 are the same version.
  private static func padded(_ a: AppVersion, _ b: AppVersion) -> ([Int], [Int]) {
    let count = max(a.parts.count, b.parts.count)
    let pad = { (parts: [Int]) in parts + Array(repeating: 0, count: count - parts.count) }
    return (pad(a.parts), pad(b.parts))
  }

  static func == (a: AppVersion, b: AppVersion) -> Bool {
    let (a, b) = padded(a, b)
    return a == b
  }

  static func < (a: AppVersion, b: AppVersion) -> Bool {
    let (a, b) = padded(a, b)
    return a.lexicographicallyPrecedes(b)
  }
}

/// The parts of GitHub's latest-release response the updater needs.
struct LatestRelease: Decodable, Equatable, Sendable {
  struct Asset: Decodable, Equatable, Sendable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
      case name
      case browserDownloadURL = "browser_download_url"
    }
  }

  let tagName: String
  let htmlURL: URL
  let assets: [Asset]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case htmlURL = "html_url"
    case assets
  }

  /// The version as the bundle spells it, without the tag's `v`.
  var versionText: String {
    tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
  }

  var version: AppVersion? {
    AppVersion(tagName)
  }

  /// The archive the release workflow uploads, named after the version.
  var archiveURL: URL? {
    assets.first { $0.name == "StockFloat-\(versionText).zip" }?.browserDownloadURL
  }
}

enum UpdateError: LocalizedError {
  case download
  case missingApp
  case wrongApp
  case wrongVersion
  case command(String)

  var errorDescription: String? {
    switch self {
    case .download: "The download failed."
    case .missingApp: "The archive does not contain StockFloat.app."
    case .wrongApp: "The archive contains a different app."
    case .wrongVersion: "The archive contains a different version."
    case .command(let tool): "\(tool) failed."
    }
  }
}

/// Checks GitHub for a newer release and installs it in place of the running app.
@MainActor
@Observable
final class Updater {
  enum State: Equatable {
    case idle
    case available(LatestRelease)
    case installing
  }

  private(set) var state: State = .idle

  @ObservationIgnored private var task: Task<Void, Never>?

  nonisolated private static let latestURL = URL(string: "https://api.github.com/repos/lesenelir/stock-float/releases/latest")!
  private static let checkInterval: Duration = .seconds(24 * 60 * 60)

  /// The release to offer, if there is one and it is not already being installed.
  var available: LatestRelease? {
    if case .available(let release) = state { release } else { nil }
  }

  /// Check now and then once a day. A build run outside a bundle has no version to compare, so it never checks.
  func start() {
    guard task == nil, Bundle.main.bundleURL.pathExtension == "app",
      let current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        .flatMap(AppVersion.init)
    else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        // A failed check is not worth reporting; the next one will try again.
        if let release = try? await Self.fetchLatest(), let latest = release.version, latest > current,
          let self, self.state != .installing
        {
          self.state = .available(release)
        }
        try? await Task.sleep(for: Self.checkInterval)
      }
    }
  }

  /// Download, check and swap in the offered release, then relaunch. Falls back to the release page when the app
  /// cannot replace itself.
  func install(strings: Strings) {
    guard case .available(let release) = state else { return }
    let target = Bundle.main.bundleURL
    guard Self.canReplace(target), let archive = release.archiveURL else {
      NSWorkspace.shared.open(release.htmlURL)
      return
    }
    state = .installing
    Task {
      // Unpacked next to the app, so the swap is a rename on the same volume.
      let work = try? FileManager.default.url(
        for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
      defer { work.map { try? FileManager.default.removeItem(at: $0) } }
      do {
        guard let work else { throw UpdateError.download }
        let app = try await Self.unpack(
          archive, into: work, version: release.versionText, bundleIdentifier: Bundle.main.bundleIdentifier)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: app)
        // Removed here as well: terminating does not wait for the defer.
        try? FileManager.default.removeItem(at: work)
        try Self.relaunch(target)
      } catch {
        state = .available(release)
        showFailure(error, release: release, strings: strings)
      }
    }
  }

  private func showFailure(_ error: Error, release: LatestRelease, strings: Strings) {
    let alert = NSAlert()
    alert.messageText = strings.updateFailed
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: strings.openDownloadPage)
    alert.addButton(withTitle: strings.cancel)
    NSApp.activate()
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(release.htmlURL)
    }
  }

  // A translocated copy runs from a read-only mount, and a non-admin user cannot write to /Applications.
  private static func canReplace(_ app: URL) -> Bool {
    let manager = FileManager.default
    return !app.path.contains("/AppTranslocation/")
      && manager.isWritableFile(atPath: app.path)
      && manager.isWritableFile(atPath: app.deletingLastPathComponent().path)
  }

  nonisolated private static func fetchLatest() async throws -> LatestRelease {
    var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(LatestRelease.self, from: data)
  }

  /// Download and unpack the archive into `work`, returning the checked app inside it.
  nonisolated private static func unpack(
    _ archive: URL, into work: URL, version: String, bundleIdentifier: String?
  ) async throws -> URL {
    let (file, response) = try await URLSession.shared.download(from: archive)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.download }
    let zip = work.appending(path: "update.zip")
    try FileManager.default.moveItem(at: file, to: zip)
    try await run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
    let app = work.appending(path: "StockFloat.app")
    try validate(app: app, bundleIdentifier: bundleIdentifier, version: version)
    try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    return app
  }

  /// Whether `app` is this app at the expected version.
  nonisolated static func validate(app: URL, bundleIdentifier: String?, version: String) throws {
    guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) else {
      throw UpdateError.missingApp
    }
    guard let bundleIdentifier, info["CFBundleIdentifier"] as? String == bundleIdentifier else {
      throw UpdateError.wrongApp
    }
    guard info["CFBundleShortVersionString"] as? String == version else { throw UpdateError.wrongVersion }
  }

  nonisolated private static func run(_ tool: String, _ arguments: [String]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: tool)
      process.arguments = arguments
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      process.terminationHandler = { process in
        if process.terminationStatus == 0 {
          continuation.resume()
        } else {
          continuation.resume(throwing: UpdateError.command(URL(fileURLWithPath: tool).lastPathComponent))
        }
      }
      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // A shell outlives this process, waits for it to exit, then opens the new copy.
  private static func relaunch(_ app: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
      "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; open \"$2\"", "sh",
      String(ProcessInfo.processInfo.processIdentifier), app.path,
    ]
    try process.run()
    NSApp.terminate(nil)
  }
}
