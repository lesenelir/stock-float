// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "StockFloat",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "StockFloat"),
    .testTarget(name: "StockFloatTests", dependencies: ["StockFloat"]),
  ]
)
