// Renders the 1024px app icon PNG. Usage: swift make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.62, blue: 1.0, alpha: 1),
           ending: NSColor(calibratedRed: 0.42, green: 0.27, blue: 0.95, alpha: 1))!
    .draw(in: shape, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = sym.size
    sym.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
