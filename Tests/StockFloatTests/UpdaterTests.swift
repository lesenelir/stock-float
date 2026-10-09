import Foundation
import Testing

@testable import StockFloat

@Test func comparesVersionsPartByPart() throws {
  let v = { (text: String) in try #require(AppVersion(text)) }

  #expect(try v("v0.2.4") > v("0.2.3"))
  #expect(try v("0.10.0") > v("0.9.9"))
  #expect(try v("1.0") > v("0.99.99"))
  #expect(try v("0.2") == v("0.2.0"))
  #expect(try !(v("0.2.3") < v("v0.2.3")))
}

@Test(arguments: ["", "v", "0.2.", "0..2", "0.2.x", "0.0.0-dev", "-1.0"])
func rejectsMalformedVersions(text: String) {
  #expect(AppVersion(text) == nil)
}

@Test func readsTheLatestRelease() throws {
  let json = """
    {
      "tag_name": "v0.2.4",
      "html_url": "https://github.com/lesenelir/stock-float/releases/tag/v0.2.4",
      "name": "StockFloat 0.2.4",
      "assets": [
        {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
        {"name": "StockFloat-0.2.4.zip", "browser_download_url": "https://example.com/StockFloat-0.2.4.zip"}
      ]
    }
    """
  let release = try JSONDecoder().decode(LatestRelease.self, from: Data(json.utf8))

  #expect(release.versionText == "0.2.4")
  #expect(release.version == AppVersion("0.2.4"))
  #expect(release.htmlURL.absoluteString == "https://github.com/lesenelir/stock-float/releases/tag/v0.2.4")
  #expect(release.archiveURL?.absoluteString == "https://example.com/StockFloat-0.2.4.zip")
}

@Test func findsNoArchiveForAnotherVersion() throws {
  let json = """
    {"tag_name": "v0.2.4", "html_url": "https://example.com", "assets": [
      {"name": "StockFloat-0.2.3.zip", "browser_download_url": "https://example.com/StockFloat-0.2.3.zip"}
    ]}
    """
  let release = try JSONDecoder().decode(LatestRelease.self, from: Data(json.utf8))

  #expect(release.archiveURL == nil)
}

@Test func acceptsOnlyThisAppAtTheExpectedVersion() throws {
  let app = FileManager.default.temporaryDirectory.appending(path: "UpdaterTests-\(UUID().uuidString)/StockFloat.app")
  defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
  try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
  let info: NSDictionary = ["CFBundleIdentifier": "com.lesenelir.stockfloat", "CFBundleShortVersionString": "0.2.4"]
  try info.write(to: app.appending(path: "Contents/Info.plist"))

  #expect(throws: Never.self) {
    try Updater.validate(app: app, bundleIdentifier: "com.lesenelir.stockfloat", version: "0.2.4")
  }
  #expect(throws: UpdateError.self) {
    try Updater.validate(app: app, bundleIdentifier: "com.example.other", version: "0.2.4")
  }
  #expect(throws: UpdateError.self) {
    try Updater.validate(app: app, bundleIdentifier: nil, version: "0.2.4")
  }
  #expect(throws: UpdateError.self) {
    try Updater.validate(app: app, bundleIdentifier: "com.lesenelir.stockfloat", version: "0.2.5")
  }
  #expect(throws: UpdateError.self) {
    try Updater.validate(app: app.appending(path: "missing"), bundleIdentifier: "com.lesenelir.stockfloat", version: "0.2.4")
  }
}
