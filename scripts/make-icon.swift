// Tickfin original vector artwork. Run: swift scripts/make-icon.swift Resources
// Then: iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit
import Foundation

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources", isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(_ size: NSSize, pixelsPerPoint scale: CGFloat = 1, to url: URL, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    draw()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
func stroke(_ points: [NSPoint], width: CGFloat, ink: NSColor) {
    let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
    path.move(to: points[0])
    if points.count == 4 { path.curve(to: points[3], controlPoint1: points[1], controlPoint2: points[2]) }
    else { points.dropFirst().forEach { path.line(to: $0) } }
    ink.setStroke(); path.stroke()
}
func point(_ x: CGFloat, _ top: CGFloat) -> NSPoint { NSPoint(x: x, y: 1024 - top) }
func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ ink: NSColor) {
    ink.setFill(); NSBezierPath(ovalIn: NSRect(x: x-radius, y: 1024-y-radius, width: radius*2, height: radius*2)).fill()
}
func rounded(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ ink: NSColor) {
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: 1024-top-h, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func candle(_ x: CGFloat, top: CGFloat, bottom: CGFloat, high: CGFloat, low: CGFloat, width: CGFloat, ink: NSColor) {
    stroke([point(x, high), point(x, low)], width: width * 0.23, ink: ink)
    rounded(x-width/2, top, width, bottom-top, width * 0.16, ink)
}
func mark() {
    let ivory = color(0xF5F2E8)
    let red = color(0xF38D73), green = color(0x83C6AD)
    // A fish silhouette anchors the identity; candlesticks carry its body.
    let body = NSBezierPath()
    body.move(to: point(342, 512))
    body.curve(to: point(814, 512), controlPoint1: point(427, 288), controlPoint2: point(687, 285))
    body.curve(to: point(342, 512), controlPoint1: point(680, 734), controlPoint2: point(424, 732))
    body.close(); body.lineWidth = 19
    ivory.withAlphaComponent(0.34).setStroke(); body.stroke()
    let tail = NSBezierPath()
    tail.move(to: point(233, 410)); tail.line(to: point(351, 484)); tail.line(to: point(351, 542)); tail.line(to: point(233, 618)); tail.close()
    ivory.setFill(); tail.fill()
    candle(429, top: 463, bottom: 599, high: 414, low: 642, width: 67, ink: red)
    candle(548, top: 387, bottom: 552, high: 337, low: 619, width: 75, ink: green)
    candle(667, top: 432, bottom: 568, high: 388, low: 612, width: 67, ink: red)
    dot(762, 505, 14, ivory)
}
func appIcon(in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform(); transform.translateX(by: rect.minX, yBy: rect.minY)
    transform.scaleX(by: rect.width / 1024, yBy: rect.height / 1024); transform.concat()
    let box = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 194, yRadius: 194)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowOffset = NSSize(width: 0, height: -13); shadow.shadowBlurRadius = 25
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.20); shadow.set()
    color(0x102331).setFill(); box.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x102331), ending: color(0x283F52))!.draw(in: box, angle: 90)
    NSColor.white.withAlphaComponent(0.16).setStroke(); box.lineWidth = 3; box.stroke()
    mark()
    NSGraphicsContext.restoreGraphicsState()
}
func menuMark() {
    let ink = NSColor.black
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: 16-y) }
    let tail = NSBezierPath(); tail.move(to: p(0.8, 5)); tail.line(to: p(3.3, 7)); tail.line(to: p(3.3, 9)); tail.line(to: p(0.8, 11)); tail.close(); ink.setFill(); tail.fill()
    for (x, top, bottom, high, low): (CGFloat,CGFloat,CGFloat,CGFloat,CGFloat) in [(5.5,7,11,5,13),(9.5,4,9,2,12),(13.5,6,10,4,12)] {
        stroke([p(x,high),p(x,low)],width:1,ink:ink)
        ink.setFill();NSBezierPath(roundedRect:NSRect(x:x-1.2,y:16-bottom,width:2.4,height:bottom-top),xRadius:0.5,yRadius:0.5).fill()
    }
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = CGFloat(points * scale)
        try png(NSSize(width: size, height: size), to: iconset.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png")) {
            appIcon(in: NSRect(x: 0, y: 0, width: size, height: size))
        }
    }
}
try png(NSSize(width: 1024, height: 1024), to: output.appendingPathComponent("app-icon-1024.png")) {
    appIcon(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
}
for scale in [1, 2] {
    try png(NSSize(width: 16, height: 16), pixelsPerPoint: CGFloat(scale), to: output.appendingPathComponent("MenuBarTemplate\(scale == 2 ? "@2x" : "").png")) { menuMark() }
}
