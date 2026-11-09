// Adds the DaboPrint3D badge (orange thumbs-up in a teal ring, the same one used by
// GoPro Connector) to the bottom-right corner of a 1024×1024 icon image.
// Usage: swift tools/add_badge.swift <icon-without-badge.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let base = NSImage(contentsOfFile: args[1]) else {
    print("Usage: swift tools/add_badge.swift <icon-without-badge.png> <output.png>"); exit(1)
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func circle(_ c: NSPoint, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

func withShadow(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

// DaboPrint3D logo colours
let orangeLight = rgb(0xFFA448)
let orange = rgb(0xF47F22)
let orangeDark = rgb(0xD95F12)
let ink = rgb(0x1E1E1E)
let teal = rgb(0x2AA8A2)

/// Cartoon thumbs-up (thick dark outline, orange gradient), in a local ~1000×1000 coordinate system.
func drawThumbsUp() {
    let ow: CGFloat = 30  // outline width

    // Cuff + palm + thumb: one shape with a single outer outline
    let cuff = rounded(150, 230, 200, 330, 55)
    let palm = rounded(270, 210, 370, 440, 140)
    let thumb = rounded(370, 520, 195, 410, 97)
    let body = NSBezierPath()
    body.append(cuff); body.append(palm); body.append(thumb)

    ink.setStroke()
    body.lineWidth = ow * 2
    body.lineJoinStyle = .round
    body.stroke()
    NSGradient(colors: [orangeLight, orange, orangeDark])!.draw(in: body, angle: -65)

    // Slightly darker cuff, with the dark rim of the opening
    orangeDark.withAlphaComponent(0.35).setFill()
    rounded(150, 230, 190, 330, 55).fill()
    ink.setFill()
    rounded(130, 214, 64, 362, 32).fill()
    ink.setStroke()
    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: 340, y: 250))
    seam.curve(to: NSPoint(x: 340, y: 540), controlPoint1: NSPoint(x: 356, y: 340), controlPoint2: NSPoint(x: 356, y: 450))
    seam.lineWidth = ow * 0.5
    seam.lineCapStyle = .round
    seam.stroke()

    // Crease between thumb and index finger
    let crease = NSBezierPath()
    crease.move(to: NSPoint(x: 400, y: 480))
    crease.curve(to: NSPoint(x: 515, y: 560), controlPoint1: NSPoint(x: 450, y: 478), controlPoint2: NSPoint(x: 495, y: 510))
    crease.lineWidth = ow * 0.65
    crease.lineCapStyle = .round
    crease.stroke()

    // Four curled fingers, from the lowest to the highest (the index finger is on top)
    let fingers: [(CGFloat, CGFloat, CGFloat)] = [  // x, y, width
        (505, 212, 225), (515, 330, 250), (515, 448, 262), (500, 566, 272),
    ]
    for (x, y, w) in fingers {
        let f = rounded(x, y, w, 128, 64)
        NSGradient(colors: [orangeLight, orange, orangeDark])!.draw(in: f, angle: -80)
        ink.setStroke()
        f.lineWidth = ow
        f.stroke()
        rgb(0xFFFFFF, 0.35).setFill()  // highlight on the knuckles
        NSBezierPath(ovalIn: NSRect(x: x + w - 100, y: y + 74, width: 58, height: 24)).fill()
    }

    // Glossy highlight on the thumb
    rgb(0xFFFFFF, 0.55).setFill()
    NSBezierPath(ovalIn: NSRect(x: 405, y: 750, width: 50, height: 130)).fill()
}

/// Badge centre and scale on the 1024×1024 canvas (origin at the bottom left).
let badgeCenter = NSPoint(x: 752, y: 272)

func drawBadge() {
    let b = badgeCenter
    withShadow(blur: 20, dy: -8, alpha: 0.40) { ink.setFill(); circle(b, 152).fill() }
    teal.setFill(); circle(b, 146).fill()
    ink.setFill(); circle(b, 125).fill()
    NSColor.white.setFill(); circle(b, 121).fill()

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: b.x + 2, y: b.y + 12)
    ctx.rotate(by: -8 * .pi / 180)
    ctx.scaleBy(x: 0.26, y: 0.26)
    ctx.translateBy(x: -455, y: -568)
    drawThumbsUp()
    ctx.restoreGState()
}

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high
base.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
drawBadge()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Created \(args[2])")
