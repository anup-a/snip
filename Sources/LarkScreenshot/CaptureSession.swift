import AppKit

/// One screenshot pass: an overlay window per display, torn down on finish.
final class CaptureSession {
    let previousApp = NSWorkspace.shared.frontmostApplication
    private var windows: [OverlayWindow] = []
    private let onEnd: () -> Void

    init(shots: [ScreenShot], onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        let rects = ScreenCapturer.windowRects()
        windows = shots.map { OverlayWindow(shot: $0, windowRects: rects, session: self) }
    }

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        for window in windows {
            window.orderFrontRegardless()
            window.overlay.syncMouse()
        }
        let mouse = NSEvent.mouseLocation
        let target = windows.first { $0.frame.contains(mouse) } ?? windows.first
        target?.makeKey()
        target?.makeFirstResponder(target?.overlay)
        NSCursor.crosshair.set()
    }

    /// The display that owns the current selection, if any.
    var activeOverlay: OverlayView? {
        windows.map(\.overlay).first { $0.phase != .hover }
    }

    func refreshAll() {
        for window in windows { window.overlay.needsDisplay = true }
    }

    func cancel() { finish() }

    func finish(restoreFocus: Bool = true) {
        guard !windows.isEmpty else { return }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        if restoreFocus { previousApp?.activate() }
        onEnd()
    }
}

/// A non-activating panel can become key (for keyboard shortcuts) even when the app isn't active.
final class OverlayWindow: NSPanel {
    let overlay: OverlayView

    init(shot: ScreenShot, windowRects: [CGRect], session: CaptureSession) {
        let frame = shot.screen.frame
        let local = windowRects
            .map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
            .filter { $0.intersects(CGRect(origin: .zero, size: frame.size)) }
        overlay = OverlayView(shot: shot, windowRects: local, session: session)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)

        // The frozen screenshot lives in a layer; the overlay only draws chrome on top.
        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.contents = shot.image
        container.layer?.contentsGravity = .resize
        container.layer?.contentsScale = shot.scale
        overlay.frame = container.bounds
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(overlay)
        contentView = container
        setFrame(frame, display: false)
        initialFirstResponder = overlay
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
