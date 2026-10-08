import AppKit
import SnipKit

/// A screenshot pinned above everything. Drag to move, scroll to zoom, double-click or Esc to close.
final class PinWindow: NSPanel {
    private static var pins: [PinWindow] = []

    let image: CGImage
    let pointSize: CGSize
    private var zoom: CGFloat = 1

    static func show(image: CGImage, pointSize: CGSize, frame: CGRect) {
        let pin = PinWindow(image: image, pointSize: pointSize, frame: frame)
        pins.append(pin)
        pin.orderFrontRegardless()
        pin.makeKey()
    }

    private init(image: CGImage, pointSize: CGSize, frame: CGRect) {
        self.image = image
        self.pointSize = pointSize
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = PinView(pin: self)
    }

    override var canBecomeKey: Bool { true }

    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.2), 5)
        let top = frame.maxY
        let size = CGSize(width: pointSize.width * zoom, height: pointSize.height * zoom)
        setFrame(CGRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    var currentZoom: CGFloat { zoom }

    override func close() {
        super.close()
        PinWindow.pins.removeAll { $0 === self }
    }
}

private final class PinView: NSView {
    private unowned let pin: PinWindow

    init(pin: PinWindow) {
        self.pin = pin
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = pin.image
        layer?.contentsGravity = .resize
        layer?.borderColor = accentBlue.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            pin.close()
        } else {
            window?.makeKey()
            window?.makeFirstResponder(self)
            window?.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        pin.setZoom(pin.currentZoom * (1 + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)))
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()
        if event.keyCode == 53 { pin.close() }
        else if event.modifierFlags.contains(.command) && key == "c" { copyImage() }
        else if event.modifierFlags.contains(.command) && key == "s" { saveImage() }
        else { super.keyDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "c").target = self
        menu.addItem(withTitle: "Save…", action: #selector(saveImage), keyEquivalent: "s").target = self
        menu.addItem(withTitle: "Actual Size", action: #selector(actualSize), keyEquivalent: "0").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copyImage() {
        Output.copyImage(pin.image, pointSize: pin.pointSize)
        Output.toast("Copied")
    }

    @objc private func saveImage() { Output.save(pin.image, pointSize: pin.pointSize) }
    @objc private func actualSize() { pin.setZoom(1) }
    @objc private func closePin() { pin.close() }
}
