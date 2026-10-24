import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let box = NSRect(x: Double(size) * 0.07, y: Double(size) * 0.07, width: Double(size) * 0.86, height: Double(size) * 0.86)
        NSColor(srgbRed: 0.08, green: 0.39, blue: 0.79, alpha: 1).setFill()
        NSBezierPath(roundedRect: box, xRadius: Double(size) * 0.2, yRadius: Double(size) * 0.2).fill()
        let symbol = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: Double(size) * 0.45, weight: .semibold))!
        let symbolSize = symbol.size
        let dest = NSRect(x: (Double(size) - symbolSize.width) / 2, y: (Double(size) - symbolSize.height) / 2,
                          width: symbolSize.width, height: symbolSize.height)
        symbol.draw(in: dest)
        NSColor.white.setFill()
        dest.fill(using: .sourceAtop)
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
