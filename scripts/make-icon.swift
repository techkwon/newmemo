import AppKit

// Draw a native document icon at each required size; no external assets.
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in [
  ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
  ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let s = CGFloat(size)
  NSAffineTransform(transform: .init(m11: s / 1024, m12: 0, m21: 0, m22: s / 1024, tX: 0, tY: 0))
    .concat()
  let background = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 210, yRadius: 210)
  NSGradient(
    starting: NSColor(calibratedRed: 0.20, green: 0.51, blue: 1, alpha: 1),
    ending: NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.83, alpha: 1))!.draw(
      in: background, angle: -65)
  NSColor.white.setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 275, y: 216, width: 474, height: 612), xRadius: 42, yRadius: 42
  ).fill()
  NSColor(calibratedRed: 0.77, green: 0.85, blue: 0.98, alpha: 1).setFill()
  for y in [660, 555, 450] {
    NSBezierPath(
      roundedRect: NSRect(x: 352, y: y, width: 310, height: 25), xRadius: 12, yRadius: 12
    ).fill()
  }
  NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.9, alpha: 1).setStroke()
  let plus = NSBezierPath()
  plus.lineWidth = 34
  plus.lineCapStyle = .round
  plus.move(to: NSPoint(x: 512, y: 275))
  plus.line(to: NSPoint(x: 512, y: 375))
  plus.move(to: NSPoint(x: 462, y: 325))
  plus.line(to: NSPoint(x: 562, y: 325))
  plus.stroke()
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(
    to: iconset.appendingPathComponent(name + ".png"))
}
