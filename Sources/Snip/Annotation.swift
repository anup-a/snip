import AppKit

let accentBlue = NSColor(srgbRed: 0x33 / 255, green: 0x70 / 255, blue: 0xFF / 255, alpha: 1)

let palette: [NSColor] = [
    NSColor(srgbRed: 0xF5 / 255, green: 0x4A / 255, blue: 0x45 / 255, alpha: 1), // red
    NSColor(srgbRed: 0xFF / 255, green: 0xC6 / 255, blue: 0x0A / 255, alpha: 1), // yellow
    accentBlue,
    NSColor(srgbRed: 0x34 / 255, green: 0xC7 / 255, blue: 0x24 / 255, alpha: 1), // green
    NSColor(srgbRed: 0x1F / 255, green: 0x23 / 255, blue: 0x29 / 255, alpha: 1), // black
    .white,
]

enum Tool: CaseIterable {
    case rect, ellipse, arrow, pen, mosaic, text, marker

    var symbol: String {
        switch self {
        case .rect: "square"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .pen: "pencil.tip"
        case .mosaic: "checkerboard.rectangle"
        case .text: "textformat"
        case .marker: "1.circle"
        }
    }

    var tip: String {
        switch self {
        case .rect: "Rectangle"
        case .ellipse: "Ellipse"
        case .arrow: "Arrow"
        case .pen: "Pen"
        case .mosaic: "Mosaic"
        case .text: "Text"
        case .marker: "Numbered marker"
        }
    }
}

enum Annotation {
    case rect(CGRect, NSColor, CGFloat)
    case ellipse(CGRect, NSColor, CGFloat)
    case arrow(CGPoint, CGPoint, NSColor, CGFloat)
    case pen([CGPoint], NSColor, CGFloat)
    case mosaic([CGPoint], CGFloat)
    case text(String, CGRect, NSColor, CGFloat)
    case marker(Int, CGPoint, NSColor, CGFloat)

    var isMarker: Bool {
        if case .marker = self { return true }
        return false
    }

    var isMeaningful: Bool {
        switch self {
        case let .rect(r, _, _), let .ellipse(r, _, _): r.width > 2 || r.height > 2
        case let .arrow(a, b, _, _): hypot(b.x - a.x, b.y - a.y) > 3
        default: true
        }
    }

    /// Draws into the current NSGraphicsContext using overlay (view) coordinates.
    func draw(mosaic: CGImage?, canvas: CGRect) {
        switch self {
        case let .rect(r, color, width):
            color.setStroke()
            let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            path.lineWidth = width
            path.stroke()
        case let .ellipse(r, color, width):
            color.setStroke()
            let path = NSBezierPath(ovalIn: r)
            path.lineWidth = width
            path.stroke()
        case let .arrow(from, to, color, width):
            Annotation.arrowPath(from: from, to: to, width: width)?.fill(color)
        case let .pen(points, color, width):
            color.setStroke()
            let path = Annotation.polyline(points)
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case let .mosaic(points, width):
            guard let mosaic, let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState()
            ctx.addPath(Annotation.polyline(points).cgPath)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.interpolationQuality = .none
            ctx.draw(mosaic, in: canvas)
            ctx.restoreGState()
        case let .text(string, frame, color, size):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .medium),
                .foregroundColor: color,
            ]
            (string as NSString).draw(in: CGRect(x: frame.minX + 2, y: frame.minY, width: 10_000, height: frame.height),
                                      withAttributes: attrs)
        case let .marker(number, center, color, radius):
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            let text = "\(number)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: radius * 1.15, weight: .bold),
                .foregroundColor: color.isLight ? NSColor.black : NSColor.white,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
        }
    }

    static func polyline(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.line(to: CGPoint(x: first.x + 0.1, y: first.y))
        } else {
            for p in points.dropFirst() { path.line(to: p) }
        }
        return path
    }

    /// Tapered arrow with a filled head.
    static func arrowPath(from: CGPoint, to: CGPoint, width: CGFloat) -> NSBezierPath? {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 1 else { return nil }
        let ux = dx / length, uy = dy / length
        let nx = -uy, ny = ux
        let headLength = min(length, 10 + width * 3.5)
        let headHalf = headLength * 0.55
        let shaftHalf = width * 0.75
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        func pt(_ p: CGPoint, _ offset: CGFloat) -> CGPoint { CGPoint(x: p.x + nx * offset, y: p.y + ny * offset) }
        let path = NSBezierPath()
        path.move(to: pt(from, width * 0.15))
        path.line(to: pt(base, shaftHalf))
        path.line(to: pt(base, headHalf))
        path.line(to: to)
        path.line(to: pt(base, -headHalf))
        path.line(to: pt(base, -shaftHalf))
        path.line(to: pt(from, -width * 0.15))
        path.close()
        return path
    }
}

extension NSBezierPath {
    func fill(_ color: NSColor) {
        color.setFill()
        fill()
    }
}

extension NSColor {
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.7
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
