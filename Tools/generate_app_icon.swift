import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("usage: swift generate_app_icon.swift <output.iconset>\n", stderr)
  exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
  ("icon_16x16.png", 16),
  ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32),
  ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512),
  ("icon_512x512@2x.png", 1024),
]

for variant in variants {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: variant.pixels,
      pixelsHigh: variant.pixels,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    throw CocoaError(.fileWriteUnknown)
  }

  let size = CGFloat(variant.pixels)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))

  let inset = size * 0.055
  let iconRect = CGRect(
    x: inset,
    y: inset,
    width: size - inset * 2,
    height: size - inset * 2
  )
  let background = NSBezierPath(
    roundedRect: iconRect,
    xRadius: size * 0.225,
    yRadius: size * 0.225
  )
  NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
  background.fill()
  NSColor.white.withAlphaComponent(0.18).setStroke()
  background.lineWidth = max(1, size * 0.006)
  background.stroke()

  let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
  let waveformWidth = size * 0.48
  let barWidth = size * 0.065
  let gap =
    (waveformWidth - barWidth * CGFloat(weights.count))
    / CGFloat(weights.count - 1)
  let startX = (size - waveformWidth) / 2
  let maximumHeight = size * 0.43
  NSColor(calibratedWhite: 0.97, alpha: 1).setFill()

  for (index, weight) in weights.enumerated() {
    let height = maximumHeight * weight
    let rect = CGRect(
      x: startX + CGFloat(index) * (barWidth + gap),
      y: (size - height) / 2,
      width: barWidth,
      height: height
    )
    NSBezierPath(
      roundedRect: rect,
      xRadius: barWidth / 2,
      yRadius: barWidth / 2
    ).fill()
  }

  NSGraphicsContext.restoreGraphicsState()
  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  try data.write(to: outputURL.appendingPathComponent(variant.name))
}
