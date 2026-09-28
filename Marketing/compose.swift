import AppKit

/// Builds the 2880×1800 App Store shots from the raw overlay renders.
/// Usage: compose <raw-dir> <out-dir>
struct Frame {
    let file: String
    let title: String
    let subtitle: String
}

let frames = [
    Frame(file: "1-snap.png", title: "Snap any window", subtitle: "Press \u{2318}\u{21E7}A, then click. Or drag any area."),
    Frame(file: "2-markup.png", title: "Mark it up in seconds", subtitle: "Boxes, arrows, numbers, and text."),
    Frame(file: "3-private.png", title: "Hide what\u{2019}s private", subtitle: "Mosaic passwords and emails before you share."),
    Frame(file: "4-pin.png", title: "Pin it on top", subtitle: "Keep a snip floating while you work."),
]

let rawNames = ["dash-hover.png", "dash-annotate.png", "chat-mosaic.png", "dash-pin.png"]

let canvas = CGSize(width: 2880, height: 1800)
let card = CGRect(x: 260, y: 28, width: 2360, height: 1456)
let iconSide: CGFloat = 112
let iconRect = CGRect(x: (canvas.width - iconSide) / 2, y: 1664, width: iconSide, height: iconSide)

let iconURL = URL(fileURLWithPath: "Icons/renders/2-scissors.png")
guard let iconData = try? Data(contentsOf: iconURL),
      let iconRep = NSBitmapImageRep(data: iconData),
      let icon = iconRep.cgImage else {
    fputs("missing \(iconURL.path)\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: compose <raw-dir> <out-dir>\n", stderr)
    exit(1)
}
let rawDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (frame, rawName) in zip(frames, rawNames) {
    let rawURL = rawDir.appendingPathComponent(rawName)
    guard let data = try? Data(contentsOf: rawURL),
          let source = NSBitmapImageRep(data: data),
          let cg = source.cgImage else {
        fputs("missing \(rawURL.path)\n", stderr)
        exit(1)
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.11, green: 0.18, blue: 0.38, alpha: 1),
            CGColor(red: 0.04, green: 0.07, blue: 0.16, alpha: 1),
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: canvas.width / 2, y: canvas.height),
                           end: CGPoint(x: canvas.width / 2, y: 0), options: [])
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 0.28, green: 0.45, blue: 0.95, alpha: 0.28))
    ctx.fillEllipse(in: CGRect(x: 540, y: 280, width: 1800, height: 1100))
    ctx.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    let iconShadow = NSShadow()
    iconShadow.shadowBlurRadius = 24
    iconShadow.shadowOffset = NSSize(width: 0, height: -8)
    iconShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    iconShadow.set()
    ctx.interpolationQuality = .high
    ctx.draw(icon, in: iconRect)
    NSGraphicsContext.restoreGraphicsState()

    let title = NSAttributedString(string: frame.title, attributes: [
        .font: NSFont.systemFont(ofSize: 72, weight: .bold),
        .foregroundColor: NSColor.white,
        .kern: -1.2,
    ])
    let subtitle = NSAttributedString(string: frame.subtitle, attributes: [
        .font: NSFont.systemFont(ofSize: 32, weight: .medium),
        .foregroundColor: NSColor(white: 1, alpha: 0.72),
    ])
    let titleSize = title.size()
    let subSize = subtitle.size()
    title.draw(at: CGPoint(x: (canvas.width - titleSize.width) / 2, y: 1568))
    subtitle.draw(at: CGPoint(x: (canvas.width - subSize.width) / 2, y: 1516))

    let fitted = aspectFit(CGSize(width: cg.width, height: cg.height), in: card.insetBy(dx: 0, dy: 0))
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 70
    shadow.shadowOffset = NSSize(width: 0, height: -28)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: fitted, xRadius: 28, yRadius: 28).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: fitted, xRadius: 28, yRadius: 28).addClip()
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: fitted)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    let stroke = NSBezierPath(roundedRect: fitted.insetBy(dx: 0.5, dy: 0.5), xRadius: 28, yRadius: 28)
    stroke.lineWidth = 1
    stroke.stroke()

    NSGraphicsContext.restoreGraphicsState()
    let dest = outDir.appendingPathComponent(frame.file)
    try rep.representation(using: .png, properties: [:])!.write(to: dest)
    fputs("wrote \(dest.path)\n", stderr)
}

func aspectFit(_ image: CGSize, in box: CGRect) -> CGRect {
    let scale = min(box.width / image.width, box.height / image.height)
    let size = CGSize(width: image.width * scale, height: image.height * scale)
    return CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
}
