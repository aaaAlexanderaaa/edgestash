import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let ink = NSColor(red: 27 / 255, green: 30 / 255, blue: 36 / 255, alpha: 1)
    let rail = NSColor(red: 252 / 255, green: 133 / 255, blue: 12 / 255, alpha: 1)
    let glass = NSColor(red: 238 / 255, green: 241 / 255, blue: 244 / 255, alpha: 1)
    NSBezierPath(roundedRect: rect.insetBy(dx: 64, dy: 64), xRadius: 220, yRadius: 220).addClip()
    ink.setFill()
    rect.fill()
    let strip = NSRect(x: 64, y: 64, width: 118, height: 896)
    rail.setFill()
    NSBezierPath(rect: strip).fill()
    let window = NSRect(x: 250, y: 280, width: 560, height: 420)
    glass.setFill()
    NSBezierPath(roundedRect: window, xRadius: 48, yRadius: 48).fill()
    rail.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: 250, y: 628, width: 560, height: 72), xRadius: 0, yRadius: 0).fill()
    ink.withAlphaComponent(0.18).setFill()
    NSBezierPath(roundedRect: NSRect(x: 310, y: 360, width: 300, height: 36), xRadius: 10, yRadius: 10).fill()
    NSBezierPath(roundedRect: NSRect(x: 310, y: 420, width: 220, height: 36), xRadius: 10, yRadius: 10).fill()
    return true
}

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
    fputs("failed to rasterize icon\n", stderr)
    exit(1)
}
bitmap.size = NSSize(width: 1024, height: 1024)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}
try png.write(to: output)
