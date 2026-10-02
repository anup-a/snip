import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class OverlayView: NSView, NSTextFieldDelegate {
    enum Phase { case hover, selecting, selected }

    private enum Drag {
        case none
        case create(CGPoint)
        case move(CGPoint, CGRect)
        case resize(Int, Int, CGRect, CGPoint)
        case draw(CGPoint)
    }

    let shot: ScreenShot
    private weak var session: CaptureSession?
    private let windowRects: [CGRect]
    private lazy var bitmap = NSBitmapImageRep(cgImage: shot.image)
    private lazy var mosaicImage: CGImage? = makeMosaic()
    private var scale: CGFloat { shot.scale }

    private(set) var phase = Phase.hover
    private(set) var selection: CGRect?
    private var hoverRect: CGRect?
    private var mouse: CGPoint?
    private var drag = Drag.none
    private var annotations: [Annotation] = []
    private var current: Annotation?
    private var textField: NSTextField?

    private(set) var tool: Tool?
    private(set) var color = palette[0]
    private(set) var sizeLevel = 1

    /// Set only by DemoRenderer: the view paints the frozen screen itself for offscreen renders.
    var demoBackground: CGImage?
    /// Marketing renders hide the pixel-size chip when it would sit on top of the content.
    var demoShowsSizeLabel = true
    /// Cocoa-point offset from the cursor to the loupe. Nil uses the normal placement.
    var demoMagnifierOffset: CGPoint?

    private var toolbar: ToolbarView!
    private var options: OptionsView!
    /// How far the user has dragged the toolbar away from its default spot under the selection.
    private var toolbarOffset = CGPoint.zero

    private var strokeWidth: CGFloat { [2, 4, 6][sizeLevel] }
    private var fontSize: CGFloat { [14, 18, 24][sizeLevel] }
    private var markerRadius: CGFloat { [10, 13, 16][sizeLevel] }
    private var mosaicWidth: CGFloat { [12, 22, 36][sizeLevel] }

    init(shot: ScreenShot, windowRects: [CGRect], session: CaptureSession) {
        self.shot = shot
        self.windowRects = windowRects
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        toolbar = ToolbarView(overlay: self)
        toolbar.isHidden = true
        addSubview(toolbar)
        options = OptionsView(overlay: self)
        options.isHidden = true
        addSubview(options)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    // AppKit resets the cursor on cursor-update events; answer with ours instead of the default arrow.
    override func cursorUpdate(with event: NSEvent) {
        updateCursor(point(event))
    }

    /// Picks up the cursor position before the first mouse move so the hover highlight shows immediately.
    func syncMouse() {
        guard let window else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        mouse = bounds.contains(p) ? p : nil
        updateHover()
        needsDisplay = true
    }

    private var otherActive: Bool {
        guard let active = session?.activeOverlay else { return false }
        return active !== self
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let demoBackground { ctx.draw(demoBackground, in: bounds) }
        let highlight: CGRect? = otherActive ? nil : (selection ?? hoverRect)

        ctx.saveGState()
        ctx.addRect(bounds)
        if let highlight { ctx.addRect(highlight) }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        guard let highlight else { return }

        if let selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            for a in annotations { a.draw(mosaic: mosaicImage, canvas: bounds) }
            current?.draw(mosaic: mosaicImage, canvas: bounds)
            NSGraphicsContext.restoreGraphicsState()
        }

        selectionBlue.setStroke()
        let border = NSBezierPath(rect: highlight.insetBy(dx: -0.75, dy: -0.75))
        border.lineWidth = 1.5
        border.stroke()

        if phase == .selected { drawHandles(highlight) }
        drawSizeLabel(highlight)
        if showsMagnifier, let mouse { drawMagnifier(at: mouse) }
    }

    private var showsMagnifier: Bool {
        switch drag {
        case .resize, .create: return true
        case .none: return phase == .hover
        default: return false
        }
    }

    private func handlePoints(_ r: CGRect) -> [(Int, Int, CGPoint)] {
        var points: [(Int, Int, CGPoint)] = []
        for hx in -1...1 {
            for hy in -1...1 where !(hx == 0 && hy == 0) {
                let x = hx < 0 ? r.minX : hx == 0 ? r.midX : r.maxX
                let y = hy < 0 ? r.minY : hy == 0 ? r.midY : r.maxY
                points.append((hx, hy, CGPoint(x: x, y: y)))
            }
        }
        return points
    }

    private func drawHandles(_ r: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Corner handles sit on the border's outer edge, like Lark's.
        let r = r.insetBy(dx: -0.75, dy: -0.75)
        for (_, _, p) in handlePoints(r) {
            let dot = NSBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 2, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            dot.fill(.white)
            ctx.restoreGState()
            dot.lineWidth = 1
            selectionBlue.setStroke()
            dot.stroke()
        }
    }

    private func drawSizeLabel(_ r: CGRect) {
        guard demoShowsSizeLabel else { return }
        let text = "\(Int(round(r.width * scale))) × \(Int(round(r.height * scale)))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let box = CGSize(width: ceil(size.width) + 12, height: ceil(size.height) + 6)
        // Above the top-left corner, or tucked inside it when the selection touches the top of the screen.
        var origin = CGPoint(x: r.minX, y: r.maxY + 6)
        if origin.y + box.height > bounds.maxY { origin = CGPoint(x: r.minX + 6, y: r.maxY - box.height - 6) }
        origin.x = min(max(origin.x, bounds.minX + 2), bounds.maxX - box.width - 2)
        NSBezierPath(roundedRect: CGRect(origin: origin, size: box), xRadius: 3, yRadius: 3)
            .fill(NSColor(white: 0.1, alpha: 0.78))
        text.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 3), withAttributes: attrs)
    }

    private func pixel(at p: CGPoint) -> (x: Int, y: Int) {
        (Int(p.x * scale), Int((bounds.height - p.y) * scale))
    }

    private func color(at p: CGPoint) -> NSColor? {
        let (x, y) = pixel(at: p)
        guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh else { return nil }
        return bitmap.colorAt(x: x, y: y)
    }

    private func drawMagnifier(at p: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let zoom: CGFloat = 8
        let cols = 15, rows = 11
        let box = CGSize(width: CGFloat(cols) * zoom, height: CGFloat(rows) * zoom)
        let infoHeight: CGFloat = 50
        let total = CGSize(width: box.width, height: box.height + infoHeight)

        var origin = CGPoint(x: p.x + 20, y: p.y - 20 - total.height)
        if let demoMagnifierOffset {
            origin = CGPoint(x: p.x + demoMagnifierOffset.x, y: p.y + demoMagnifierOffset.y)
        } else {
            if origin.x + total.width > bounds.maxX { origin.x = p.x - 20 - total.width }
            if origin.y < bounds.minY { origin.y = p.y + 20 }
        }
        let zoomRect = CGRect(x: origin.x, y: origin.y + infoHeight, width: box.width, height: box.height)
        let infoRect = CGRect(x: origin.x, y: origin.y, width: box.width, height: infoHeight)

        let (px, py) = pixel(at: p)
        let src = CGRect(x: px - cols / 2, y: py - rows / 2, width: cols, height: rows)
        let imageBounds = CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height)
        let visible = src.intersection(imageBounds)

        NSBezierPath(rect: zoomRect).fill(.black)
        if !visible.isNull, let crop = shot.image.cropping(to: visible) {
            let dest = CGRect(x: zoomRect.minX + (visible.minX - src.minX) * zoom,
                              y: zoomRect.maxY - (visible.maxY - src.minY) * zoom,
                              width: visible.width * zoom, height: visible.height * zoom)
            ctx.saveGState()
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: dest)
            ctx.restoreGState()
        }
        // Crosshair through the center pixel.
        let cx = zoomRect.minX + CGFloat(cols / 2) * zoom
        let cy = zoomRect.maxY - CGFloat(rows / 2 + 1) * zoom
        let cross = accentBlue.withAlphaComponent(0.35)
        NSBezierPath(rect: CGRect(x: zoomRect.minX, y: cy, width: zoomRect.width, height: zoom)).fill(cross)
        NSBezierPath(rect: CGRect(x: cx, y: zoomRect.minY, width: zoom, height: zoomRect.height)).fill(cross)
        NSColor.white.setStroke()
        NSBezierPath(rect: zoomRect.insetBy(dx: 0.5, dy: 0.5)).stroke()

        NSBezierPath(rect: infoRect).fill(NSColor.black.withAlphaComponent(0.8))
        let pixelColor = color(at: p) ?? .black
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white,
        ]
        let dim: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        ("(\(px), \(py))" as NSString).draw(at: CGPoint(x: infoRect.minX + 6, y: infoRect.minY + 33), withAttributes: attrs)
        NSBezierPath(rect: CGRect(x: infoRect.minX + 6, y: infoRect.minY + 19, width: 10, height: 10)).fill(pixelColor)
        (pixelColor.hexString as NSString).draw(at: CGPoint(x: infoRect.minX + 21, y: infoRect.minY + 17), withAttributes: attrs)
        ("C to copy color" as NSString).draw(at: CGPoint(x: infoRect.minX + 6, y: infoRect.minY + 3), withAttributes: dim)
    }

    // MARK: Mouse

    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    private func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        let x0 = snap(min(a.x, b.x)), y0 = snap(min(a.y, b.y))
        return CGRect(x: x0, y: y0, width: snap(max(a.x, b.x)) - x0, height: snap(max(a.y, b.y)) - y0)
    }

    private func updateHover() {
        guard let mouse, phase == .hover, !otherActive else { hoverRect = nil; return }
        hoverRect = windowRects.first { $0.contains(mouse) }.map { $0.intersection(bounds) } ?? bounds
    }

    private func handle(at p: CGPoint, in r: CGRect) -> (Int, Int)? {
        for (hx, hy, h) in handlePoints(r) where abs(h.x - p.x) <= 7 && abs(h.y - p.y) <= 7 {
            return (hx, hy)
        }
        return nil
    }

    override func mouseEntered(with event: NSEvent) {
        if window?.isKeyWindow == false {
            window?.makeKey()
            window?.makeFirstResponder(self)
        }
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        if phase == .hover { hoverRect = nil }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        if window?.isKeyWindow == false {
            window?.makeKey()
            window?.makeFirstResponder(self)
        }
        let p = point(event)
        mouse = p
        updateHover()
        updateCursor(p)
        needsDisplay = true
    }

    private func updateCursor(_ p: CGPoint) {
        // Mid-drag the cursor follows the gesture, not whatever is under the pointer.
        switch drag {
        case let .resize(hx, hy, _, _): resizeCursor(hx, hy).set(); return
        case .move: NSCursor.closedHand.set(); return
        case .create: NSCursor.crosshair.set(); return
        default: break
        }
        guard phase == .selected, let sel = selection else { NSCursor.crosshair.set(); return }
        if !toolbar.isHidden && toolbar.frame.contains(p) || !options.isHidden && options.frame.contains(p) {
            (toolbar.isOverGrip(convert(p, to: toolbar)) ? NSCursor.openHand : NSCursor.arrow).set()
            return
        }
        if let (hx, hy) = handle(at: p, in: sel) {
            resizeCursor(hx, hy).set()
        } else if sel.contains(p) {
            switch tool {
            case nil: NSCursor.openHand.set()
            case .text: NSCursor.iBeam.set()
            default: NSCursor.crosshair.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    private func resizeCursor(_ hx: Int, _ hy: Int) -> NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch (hx, hy) {
            case (-1, 1): position = .topLeft
            case (1, 1): position = .topRight
            case (-1, -1): position = .bottomLeft
            case (1, -1): position = .bottomRight
            case (0, 1): position = .top
            case (0, -1): position = .bottom
            case (-1, 0): position = .left
            default: position = .right
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return hy == 0 ? .resizeLeftRight : hx == 0 ? .resizeUpDown : .crosshair
    }

    override func mouseDown(with event: NSEvent) {
        if otherActive { return }
        let p = point(event)
        mouse = p
        commitText()

        switch phase {
        case .hover:
            drag = .create(p)
        case .selecting:
            break
        case .selected:
            guard let sel = selection else { return }
            if event.clickCount == 2, tool == nil, sel.contains(p) {
                done()
                return
            }
            if let (hx, hy) = handle(at: p, in: sel) {
                drag = .resize(hx, hy, sel, p)
                resizeCursor(hx, hy).set()
            } else if let tool, sel.contains(p) {
                switch tool {
                case .text:
                    beginText(at: p)
                case .marker:
                    let number = annotations.filter(\.isMarker).count + 1
                    annotations.append(.marker(number, p, color, markerRadius))
                default:
                    drag = .draw(p)
                    current = shape(tool, from: p, to: p, constrained: false)
                }
            } else if sel.contains(p) {
                drag = .move(p, sel)
                NSCursor.closedHand.set()
            }
        }
        layoutToolbar()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        mouse = p
        switch drag {
        case .none:
            return
        case let .create(start):
            if phase == .hover && hypot(p.x - start.x, p.y - start.y) < 4 { return }
            phase = .selecting
            hoverRect = nil
            selection = rect(start, p)
            session?.refreshAll()
        case let .move(start, original):
            var r = original.offsetBy(dx: snap(p.x - start.x), dy: snap(p.y - start.y))
            r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
            r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
            selection = r
        case let .resize(hx, hy, original, start):
            var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
            let dx = p.x - start.x, dy = p.y - start.y
            if hx < 0 { minX += dx } else if hx > 0 { maxX += dx }
            if hy < 0 { minY += dy } else if hy > 0 { maxY += dy }
            selection = rect(CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY)).intersection(bounds)
        case let .draw(start):
            if let tool {
                current = shape(tool, from: start, to: p, constrained: event.modifierFlags.contains(.shift))
            }
        }
        updateCursor(p)
        layoutToolbar()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .create:
            if phase == .hover {
                selection = hoverRect ?? bounds
            } else if let sel = selection, sel.width < 3 || sel.height < 3 {
                resetSelection()
                return
            }
            phase = .selected
            hoverRect = nil
        case .draw:
            if let current, current.isMeaningful { annotations.append(current) }
            current = nil
        default:
            break
        }
        drag = .none
        layoutToolbar()
        updateCursor(point(event))
        session?.refreshAll()
    }

    override func rightMouseDown(with event: NSEvent) {
        if phase == .selected {
            resetSelection()
        } else {
            session?.cancel()
        }
    }

    private func resetSelection() {
        textField?.removeFromSuperview()
        textField = nil
        drag = .none
        toolbarOffset = .zero
        selection = nil
        annotations.removeAll()
        current = nil
        tool = nil
        phase = .hover
        updateHover()
        toolbar.refresh()
        options.refresh()
        layoutToolbar()
        session?.refreshAll()
    }

    private func shape(_ tool: Tool, from start: CGPoint, to end: CGPoint, constrained: Bool) -> Annotation? {
        var end = end
        switch tool {
        case .rect, .ellipse:
            if constrained {
                let dx = end.x - start.x, dy = end.y - start.y
                let side = max(abs(dx), abs(dy))
                end = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
            }
            let r = rect(start, end)
            return tool == .rect ? .rect(r, color, strokeWidth) : .ellipse(r, color, strokeWidth)
        case .arrow:
            if constrained {
                let angle = (atan2(end.y - start.y, end.x - start.x) / (.pi / 4)).rounded() * (.pi / 4)
                let length = hypot(end.x - start.x, end.y - start.y)
                end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
            }
            return .arrow(start, end, color, strokeWidth)
        case .pen:
            if case let .pen(points, c, w)? = current { return .pen(points + [end], c, w) }
            return .pen([start], color, strokeWidth)
        case .mosaic:
            if case let .mosaic(points, w)? = current { return .mosaic(points + [end], w) }
            return .mosaic([start], mosaicWidth)
        case .text, .marker:
            return nil
        }
    }

    // MARK: Text

    private func beginText(at p: CGPoint) {
        let height = ceil(fontSize * 1.3) + 4
        let field = NSTextField(frame: CGRect(x: p.x, y: p.y - height / 2, width: 240, height: height))
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.textColor = color
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    func controlTextDidChange(_ note: Notification) {
        guard let field = textField else { return }
        let width = (field.stringValue as NSString).size(withAttributes: [.font: field.font!]).width + 24
        field.frame.size.width = max(240, width)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) || selector == #selector(insertNewline(_:)) {
            commitText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ note: Notification) { commitText() }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty, let font = field.font, let textColor = field.textColor {
            annotations.append(.text(text, field.frame, textColor, font.pointSize))
        }
        field.removeFromSuperview()
        // Defer: the field editor is still ending its edit and would reject the focus change.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.textField == nil else { return }
            self.window?.makeFirstResponder(self)
        }
        needsDisplay = true
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch event.keyCode {
        case 53: // esc
            session?.cancel()
        case 36, 76: // return
            if phase == .selected { done() }
        case 123, 124, 125, 126: // arrows nudge the selection
            guard phase == .selected, var r = selection else { return }
            let step = (event.modifierFlags.contains(.shift) ? 10 : 1) / scale
            switch event.keyCode {
            case 123: r.origin.x -= step
            case 124: r.origin.x += step
            case 125: r.origin.y -= step
            default: r.origin.y += step
            }
            r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
            r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
            selection = r
            layoutToolbar()
            needsDisplay = true
        default:
            if command && key == "z" { undo() }
            else if command && key == "c" { if phase == .selected { done() } }
            else if command && key == "s" { if phase == .selected { save() } }
            else if !command && key == "c", phase != .selected, let mouse, let c = color(at: mouse) {
                Output.copyString(c.hexString)
                Output.toast("Copied \(c.hexString)")
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Toolbar

    private var isAdjusting: Bool {
        switch drag {
        case .create, .move, .resize: return true
        default: return false
        }
    }

    func layoutToolbar() {
        guard phase == .selected, let sel = selection, !isAdjusting else {
            toolbar.isHidden = true
            options.isHidden = true
            return
        }
        toolbar.isHidden = false
        options.isHidden = tool == nil
        let tb = toolbar.fittingSize
        let op = options.fittingSize
        let optionsHeight = tool == nil ? 0 : op.height + 6
        let block = tb.height + optionsHeight

        var top = sel.minY - 8
        if top - block < bounds.minY + 4 {
            top = sel.maxY + 8 + block
            if top > bounds.maxY - 4 { top = max(sel.minY, bounds.minY) + 8 + block }
        }
        top += toolbarOffset.y
        top = min(max(top, bounds.minY + 4 + block), bounds.maxY - 4)
        var x = sel.maxX - tb.width + toolbarOffset.x
        x = min(max(x, bounds.minX + 4), bounds.maxX - tb.width - 4)
        toolbar.frame = CGRect(x: x, y: top - tb.height, width: tb.width, height: tb.height)
        options.frame = CGRect(x: x, y: top - tb.height - 6 - op.height, width: op.width, height: op.height)
    }

    /// Called by the toolbar's grip while the user drags the bar somewhere else.
    func moveToolbar(by delta: CGPoint) {
        toolbarOffset.x += delta.x
        toolbarOffset.y += delta.y
        layoutToolbar()
    }

    func toggleTool(_ t: Tool) {
        commitText()
        tool = tool == t ? nil : t
        toolbar.refresh()
        options.refresh()
        layoutToolbar()
    }

    func setColor(_ c: NSColor) {
        color = c
        textField?.textColor = c
        options.refresh()
    }

    func setSizeLevel(_ level: Int) {
        sizeLevel = level
        textField?.font = .systemFont(ofSize: fontSize, weight: .medium)
        options.refresh()
    }

    func undo() {
        if textField != nil {
            textField?.removeFromSuperview()
            textField = nil
            window?.makeFirstResponder(self)
        } else if !annotations.isEmpty {
            annotations.removeLast()
        } else if phase == .selected {
            resetSelection()
            return
        }
        needsDisplay = true
    }

    // MARK: Output

    private func makeMosaic() -> CGImage? {
        let input = CIImage(cgImage: shot.image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(6 * scale)
        filter.center = .zero
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }

    /// Crops the frozen screen to the selection and burns in annotations at full pixel density.
    func renderSelection() -> CGImage? {
        guard let sel = selection else { return nil }
        let pixelRect = CGRect(x: sel.minX * scale, y: (bounds.height - sel.maxY) * scale,
                               width: sel.width * scale, height: sel.height * scale).integral
        guard let base = shot.image.cropping(to: pixelRect) else { return nil }
        guard !annotations.isEmpty else { return base }
        let space = shot.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return base }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -pixelRect.minX / scale, y: -(bounds.height * scale - pixelRect.maxY) / scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for a in annotations { a.draw(mosaic: mosaicImage, canvas: bounds) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? base
    }

    private func finishedImage() -> (CGImage, CGSize)? {
        commitText()
        guard let sel = selection, let image = renderSelection() else { return nil }
        return (image, sel.size)
    }

    func done() {
        guard let (image, size) = finishedImage() else { return }
        Output.copyImage(image, pointSize: size)
        session?.finish()
    }

    func save() {
        guard let (image, size) = finishedImage() else { return }
        let previous = session?.previousApp
        session?.finish(restoreFocus: false)
        Output.save(image, pointSize: size)
        previous?.activate()
    }

    func pin() {
        guard let (image, size) = finishedImage(), let sel = selection else { return }
        let frame = sel.offsetBy(dx: shot.frame.minX, dy: shot.frame.minY)
        session?.finish()
        PinWindow.show(image: image, pointSize: size, frame: frame)
    }

    func recognizeText() {
        guard let (image, _) = finishedImage() else { return }
        session?.finish(restoreFocus: false)
        Output.recognizeText(in: image)
    }

    func cancel() { session?.cancel() }
}

// MARK: Demo rendering

extension OverlayView {
    /// Puts the overlay into a scripted state for offscreen marketing renders.
    func applyDemoState(selection: CGRect?, mouse: CGPoint?, annotations: [Annotation], tool: Tool?, color: NSColor, sizeLevel: Int) {
        self.selection = selection
        self.mouse = mouse
        self.annotations = annotations
        self.tool = tool
        self.color = color
        self.sizeLevel = sizeLevel
        phase = selection == nil ? .hover : .selected
        updateHover()
        toolbar.refresh()
        options.refresh()
        layoutToolbar()
        needsDisplay = true
    }

    var visibleBarFrames: [CGRect] {
        [toolbar, options].compactMap { $0 }.filter { !$0.isHidden }.map(\.frame)
    }
}
