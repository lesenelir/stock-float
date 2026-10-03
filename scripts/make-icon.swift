// Turn the full-bleed icon artwork into the app icon:
//   swift scripts/make-icon.swift Resources/icon-source.png Resources/AppIcon.icns docs/icon.png
// The artwork is masked to the macOS icon shape (an 824-point rounded square on a 1024 canvas) with a soft shadow.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
  FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift <artwork.png> <AppIcon.icns> <preview.png>\n".utf8))
  exit(1)
}
guard let artwork = NSImage(contentsOfFile: arguments[1]) else {
  FileHandle.standardError.write(Data("Cannot read \(arguments[1])\n".utf8))
  exit(1)
}

/// Render the icon at `pixels` square; everything is laid out on a 1024-point canvas.
func render(pixels: Int) -> Data? {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else { return nil }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

  let body = NSRect(x: 100, y: 100, width: 824, height: 824)
  let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
  shadow.shadowOffset = NSSize(width: 0, height: -12)
  shadow.shadowBlurRadius = 24
  shadow.set()
  NSColor.black.setFill()
  shape.fill()
  NSGraphicsContext.restoreGraphicsState()

  NSGraphicsContext.saveGraphicsState()
  shape.addClip()
  artwork.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()

  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])
}

// iconutil wants exactly these names; each point size comes at 1x and 2x.
let iconset = FileManager.default.temporaryDirectory.appending(path: "StockFloat-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    guard let data = render(pixels: points * scale) else { exit(1) }
    let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
    try data.write(to: iconset.appending(path: name))
  }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", arguments[2]]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(1) }

guard let preview = render(pixels: 256) else { exit(1) }
try preview.write(to: URL(fileURLWithPath: arguments[3]))
print("Wrote \(arguments[2]) and \(arguments[3])")
