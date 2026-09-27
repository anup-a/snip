import AppKit

final class IconButton: NSButton {
    var isActive = false {
        didSet {
            contentTintColor = isActive ? larkBlue : baseTint
            needsDisplay = true
        }
    }
    private let baseTint: NSColor
    private let handler: () -> Void

    init(symbol: String, tip: String, tint: NSColor = NSColor(white: 0.2, alpha: 1), handler: @escaping () -> Void) {
        self.baseTint = tint
        self.handler = handler
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        imagePosition = .imageOnly
        isBordered = false
        toolTip = tip
        contentTintColor = tint
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
                .fill(larkBlue.withAlphaComponent(0.12))
        }
        super.draw(dirtyRect)
    }
}

/// A button that paints itself (size dots, color swatches).
final class PaintButton: NSButton {
    var isActive = false { didSet { needsDisplay = true } }
    private let painter: (CGRect, Bool) -> Void
    private let handler: () -> Void

    init(painter: @escaping (CGRect, Bool) -> Void, handler: @escaping () -> Void) {
        self.painter = painter
        self.handler = handler
        super.init(frame: CGRect(x: 0, y: 0, width: 26, height: 26))
        isBordered = false
        title = ""
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) { painter(bounds, isActive) }
}

private func separator() -> NSView {
    let view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
    view.translatesAutoresizingMaskIntoConstraints = false
    view.widthAnchor.constraint(equalToConstant: 1).isActive = true
    view.heightAnchor.constraint(equalToConstant: 18).isActive = true
    return view
}

/// White floating panel with a horizontal row of controls.
class FloatingBar: NSView {
    let stack = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 6
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {} // don't leak clicks to the overlay
}

final class ToolbarView: FloatingBar {
    private weak var overlay: OverlayView?
    private var toolButtons: [(Tool, IconButton)] = []

    init(overlay: OverlayView) {
        self.overlay = overlay
        super.init(frame: .zero)
        for tool in Tool.allCases {
            let button = IconButton(symbol: tool.symbol, tip: tool.tip) { [weak self] in self?.overlay?.toggleTool(tool) }
            toolButtons.append((tool, button))
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(IconButton(symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)") { [weak self] in self?.overlay?.undo() })
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(IconButton(symbol: "text.viewfinder", tip: "Extract text") { [weak self] in self?.overlay?.recognizeText() })
        stack.addArrangedSubview(IconButton(symbol: "pin", tip: "Pin to screen") { [weak self] in self?.overlay?.pin() })
        stack.addArrangedSubview(IconButton(symbol: "square.and.arrow.down", tip: "Save (⌘S)") { [weak self] in self?.overlay?.save() })
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(IconButton(symbol: "xmark", tip: "Cancel (Esc)") { [weak self] in self?.overlay?.cancel() })
        stack.addArrangedSubview(IconButton(symbol: "checkmark", tip: "Copy (Enter)", tint: larkBlue) { [weak self] in self?.overlay?.done() })
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        for (tool, button) in toolButtons { button.isActive = overlay?.tool == tool }
    }
}

final class OptionsView: FloatingBar {
    private weak var overlay: OverlayView?
    private var sizeButtons: [PaintButton] = []
    private var colorButtons: [PaintButton] = []

    init(overlay: OverlayView) {
        self.overlay = overlay
        super.init(frame: .zero)
        for (level, diameter) in [4.0, 7.0, 10.0].enumerated() {
            let button = PaintButton(painter: { bounds, active in
                let dot = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
                NSBezierPath(ovalIn: dot).fill(active ? larkBlue : NSColor(white: 0.55, alpha: 1))
            }) { [weak self] in self?.overlay?.setSizeLevel(level) }
            sizeButtons.append(button)
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(separator())
        for color in palette {
            let button = PaintButton(painter: { bounds, active in
                let swatch = bounds.insetBy(dx: 6, dy: 6)
                if active {
                    let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 4, yRadius: 4)
                    ring.lineWidth = 1.5
                    larkBlue.setStroke()
                    ring.stroke()
                }
                NSBezierPath(roundedRect: swatch, xRadius: 2, yRadius: 2).fill(color)
                if color.isLight {
                    NSColor(white: 0.8, alpha: 1).setStroke()
                    NSBezierPath(roundedRect: swatch.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).stroke()
                }
            }) { [weak self] in self?.overlay?.setColor(color) }
            colorButtons.append(button)
            stack.addArrangedSubview(button)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        guard let overlay else { return }
        for (i, b) in sizeButtons.enumerated() { b.isActive = i == overlay.sizeLevel }
        for (i, b) in colorButtons.enumerated() { b.isActive = palette[i] == overlay.color }
        // Mosaic has no color.
        colorButtons.forEach { $0.isHidden = overlay.tool == .mosaic }
    }
}
