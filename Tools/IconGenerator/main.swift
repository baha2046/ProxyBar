import AppKit
import Foundation

let outputURL: URL
if CommandLine.arguments.count > 1 {
    outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build")
        .appendingPathComponent("AppIcon.icns")
}

let workURL = outputURL.deletingLastPathComponent().appendingPathComponent("ProxyBar.iconset")
try? FileManager.default.removeItem(at: workURL)
try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

let variants: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    let image = drawIcon(size: variant.size)
    let url = workURL.appendingPathComponent(variant.name)
    try writePNG(image: image, to: url)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", workURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw IconError.iconutilFailed(process.terminationStatus)
}

try? FileManager.default.removeItem(at: workURL)

private func drawIcon(size: Int) -> NSImage {
    let dimension = CGFloat(size)
    let image = NSImage(size: NSSize(width: dimension, height: dimension))

    image.lockFocus()
    NSColor(calibratedRed: 0.08, green: 0.43, blue: 0.70, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: dimension, height: dimension), xRadius: dimension * 0.22, yRadius: dimension * 0.22).fill()

    NSColor.white.setStroke()
    NSColor.white.setFill()
    let strokeWidth = max(2, dimension * 0.07)
    let inset = dimension * 0.20
    let body = NSBezierPath(roundedRect: NSRect(x: inset, y: inset * 1.1, width: dimension - inset * 2, height: dimension - inset * 2.2), xRadius: dimension * 0.11, yRadius: dimension * 0.11)
    body.lineWidth = strokeWidth
    body.stroke()

    let split = NSBezierPath()
    split.move(to: NSPoint(x: dimension / 2, y: inset * 1.1))
    split.line(to: NSPoint(x: dimension / 2, y: dimension - inset * 1.1))
    split.lineWidth = max(1.5, dimension * 0.045)
    split.stroke()

    let dotSize = dimension * 0.13
    NSBezierPath(ovalIn: NSRect(x: dimension * 0.31, y: dimension * 0.45, width: dotSize, height: dotSize)).fill()
    NSBezierPath(ovalIn: NSRect(x: dimension * 0.56, y: dimension * 0.45, width: dotSize, height: dotSize)).fill()

    image.unlockFocus()
    return image
}

private func writePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.pngEncodingFailed
    }

    try png.write(to: url)
}

private enum IconError: Error {
    case pngEncodingFailed
    case iconutilFailed(Int32)
}
