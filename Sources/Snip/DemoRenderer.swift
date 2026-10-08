import AppKit
import SnipKit

/// Renders scripted overlay states offscreen for App Store screenshots.
/// Usage: SNIP_DEMO_IMAGE=scene.png SNIP_DEMO_WINDOWS="x,y,w,h" Snip --render-demo <script> <out.png>
enum DemoRenderer {
    static func render(script: String, to path: String) {
        guard let shot = ScreenCapturer.demoShot() else {
            FileHandle.standardError.write("SNIP_DEMO_IMAGE is not set or unreadable\n".data(using: .utf8)!)
            return
        }
        let session = CaptureSession(shots: [shot]) {}
        guard let view = session.overlays.first else { return }
        view.demoBackground = shot.image
        let height = view.bounds.height
        // Scripts use top-left points, like the HTML scenes.
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: height - y - h, width: w, height: h) }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: height - y) }
        let red = palette[0]

        var pinned = false
        switch script {
        case "hover":
            view.demoShowsSizeLabel = false
            // Loupe sits to the right of the cursor, centered on the orange bar, clear of the summary.
            view.demoMagnifierOffset = CGPoint(x: 36, y: -78)
            view.applyDemoState(selection: nil, mouse: p(990, 500), annotations: [], tool: nil, color: red, sizeLevel: 1)
        case "annotate", "pin":
            view.demoShowsSizeLabel = false
            view.applyDemoState(
                selection: r(308, 124, 868, 548), mouse: nil,
                annotations: [
                    .rect(r(958, 392, 68, 180), red, 4),
                    .arrow(p(760, 622), p(944, 500), red, 4),
                    .marker(1, p(1026, 392), red, 13),
                    .text("Campaign launch", r(806, 384, 150, 30), red, 18),
                    .ellipse(r(898, 270, 118, 34), red, 4),
                    .marker(2, p(1034, 287), red, 13),
                ],
                tool: .arrow, color: red, sizeLevel: 1)
            pinned = script == "pin"
        case "mosaic":
            view.demoShowsSizeLabel = false
            view.applyDemoState(
                selection: r(340, 168, 800, 400), mouse: nil,
                annotations: [
                    .mosaic(stride(from: 455, through: 860, by: 4).map { p(CGFloat($0), 338) }, 16),
                    .mosaic(stride(from: 455, through: 860, by: 4).map { p(CGFloat($0), 350) }, 16),
                    .mosaic(stride(from: 455, through: 860, by: 4).map { p(CGFloat($0), 362) }, 16),
                    .rect(r(418, 228, 520, 64), palette[2], 4),
                    .arrow(p(1060, 310), p(948, 268), palette[2], 4),
                    .text("Fix step 2 spacing", r(968, 304, 180, 28), palette[2], 16),
                ],
                tool: .mosaic, color: palette[2], sizeLevel: 1)
        default:
            FileHandle.standardError.write("Unknown script \(script)\n".data(using: .utf8)!)
            return
        }
        view.layoutSubtreeIfNeeded()

        let size = view.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: shot.image.width, pixelsHigh: shot.image.height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.draw(shot.image, in: CGRect(origin: .zero, size: size))
        view.demoBackground = pinned ? nil : shot.image

        if pinned, let crop = view.renderSelection(), let sel = view.selection {
            // A pinned snip floating over the desktop, offset from where it was taken.
            let frame = sel.offsetBy(dx: 40, dy: -76)
            let card = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 36
            shadow.shadowOffset = NSSize(width: 0, height: -16)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
            shadow.set()
            card.fill(.white)
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            card.addClip()
            ctx.draw(crop, in: frame)
            NSGraphicsContext.restoreGraphicsState()
            accentBlue.withAlphaComponent(0.55).setStroke()
            card.lineWidth = 1
            card.stroke()
        } else {
            let overlay = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: shot.image.width, pixelsHigh: shot.image.height,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            overlay.size = size
            view.cacheDisplay(in: view.bounds, to: overlay)
            overlay.draw(in: CGRect(origin: .zero, size: size))
            // Soft shadow outside each floating bar (the bar itself is already in the overlay render).
            for bar in view.visibleBarFrames {
                NSGraphicsContext.saveGraphicsState()
                let clip = NSBezierPath(rect: CGRect(origin: .zero, size: size))
                clip.append(NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6))
                clip.windingRule = .evenOdd
                clip.addClip()
                let shadow = NSShadow()
                shadow.shadowBlurRadius = 12
                shadow.shadowOffset = NSSize(width: 0, height: -3)
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
                shadow.set()
                NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill(.white)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
