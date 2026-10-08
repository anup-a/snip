import AppKit
import SnipKit
import AVKit
import ScreenCaptureKit

/// A capture that keeps running after the overlay closes (scrolling screenshot, recording).
protocol LiveCapture: AnyObject {
    /// Stops and keeps the result. ⌘⇧A calls this while a live capture runs.
    func finish()
}

enum Live {
    static var current: LiveCapture?
}

struct LiveCaptureError: LocalizedError {
    let errorDescription: String?
}

enum LiveSource {
    /// A filter for the display under `screen` that leaves out every Snip window (shade, bars, previews).
    static func filter(for screen: NSScreen) async throws -> (SCContentFilter, SCDisplay) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == number.uint32Value })
        else { throw LiveCaptureError(errorDescription: "Display not found") }
        let own = content.applications.filter { $0.processID == getpid() }
        return (SCContentFilter(display: display, excludingApplications: own, exceptingWindows: []), display)
    }

    /// ScreenCaptureKit wants display-local points with a top-left origin.
    static func sourceRect(_ region: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(x: region.minX - screen.frame.minX, y: screen.frame.maxY - region.maxY,
               width: region.width, height: region.height)
    }
}

/// Dims the screen around a live region. Clicks and scrolls pass straight through to the apps below.
final class RegionShade: NSWindow {
    init(region: CGRect, screen: NSScreen, border: NSColor) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = ShadeView(region: region.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY), border: border)
        setFrame(screen.frame, display: false)
    }
}

private final class ShadeView: NSView {
    let region: CGRect
    let border: NSColor

    init(region: CGRect, border: NSColor) {
        self.region = region
        self.border = border
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.addRect(bounds)
        ctx.addRect(region)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)
        // Outside the region, so it never lands in the capture.
        border.setStroke()
        let path = NSBezierPath(rect: region.insetBy(dx: -1, dy: -1))
        path.lineWidth = 2
        path.stroke()
    }
}

/// A floating white bar of controls next to a live region. It never takes focus from the app being captured.
final class LiveBar: NSPanel {
    private static let margin: CGFloat = 10

    init(views: [NSView], region: CGRect, screen: NSScreen) {
        let bar = FloatingBar(frame: .zero)
        bar.stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 6)
        bar.stack.spacing = 4
        views.forEach(bar.stack.addArrangedSubview)
        let size = bar.fittingSize
        let m = LiveBar.margin
        let outer = CGSize(width: size.width + m * 2, height: size.height + m * 2)

        // Same spot as the capture toolbar: under the region, right-aligned; above it when there's no room.
        let visible = screen.visibleFrame
        var origin = CGPoint(x: region.maxX - size.width - m, y: region.minY - 8 - size.height - m)
        if origin.y + m < visible.minY { origin.y = region.maxY + 8 - m }
        if origin.y + m + size.height > visible.maxY { origin.y = region.minY + 8 - m }
        origin.x = min(max(origin.x, visible.minX - m), visible.maxX - size.width - m)

        super.init(contentRect: CGRect(origin: origin, size: outer), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let container = NSView(frame: CGRect(origin: .zero, size: outer))
        bar.frame = CGRect(x: m, y: m, width: size.width, height: size.height)
        container.addSubview(bar)
        contentView = container
    }

    override var canBecomeKey: Bool { false }

    static func label(_ text: String, monospaced: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = monospaced ? .monospacedDigitSystemFont(ofSize: 13, weight: .medium) : .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor(white: 0.2, alpha: 1)
        return label
    }
}

/// Shows a finished long screenshot, already on the clipboard.
final class ImageResultWindow: NSWindow {
    private static var open: [ImageResultWindow] = []
    private let image: CGImage
    private let pointSize: CGSize

    static func show(_ image: CGImage, pointSize: CGSize) {
        let window = ImageResultWindow(image: image, pointSize: pointSize)
        open.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private init(image: CGImage, pointSize: CGSize) {
        self.image = image
        self.pointSize = pointSize
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let shown = min(pointSize.width, 720)
        let docSize = CGSize(width: shown, height: pointSize.height * shown / pointSize.width)
        let size = CGSize(width: shown + 16, height: min(docSize.height, screen.height * 0.75) + 52)
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        title = "Scrolling Screenshot (copied)"
        isReleasedWhenClosed = false
        level = .floating

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: docSize))
        imageView.image = NSImage(cgImage: image, size: docSize)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let scroll = NSScrollView()
        scroll.documentView = FlippedClip(view: imageView)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 0.93, alpha: 1)

        let save = NSButton(title: "Save…", target: self, action: #selector(saveImage))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyImage))
        copy.keyEquivalent = "\r"
        contentView = ResultLayout.make(main: scroll, buttons: [save, copy])
    }

    @objc private func copyImage() {
        Output.copyImage(image, pointSize: pointSize)
        close()
    }

    @objc private func saveImage() {
        Output.save(image, pointSize: pointSize)
    }

    override func close() {
        super.close()
        ImageResultWindow.open.removeAll { $0 === self }
    }
}

/// Lays an image view out top-down inside a scroll view.
private final class FlippedClip: NSView {
    init(view: NSView) {
        super.init(frame: view.frame)
        addSubview(view)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
}

/// Plays a finished recording, with Save and Copy.
final class VideoResultWindow: NSWindow {
    private static var open: [VideoResultWindow] = []
    private let url: URL
    private let player: AVPlayer

    static func show(_ url: URL, pointSize: CGSize) {
        let window = VideoResultWindow(url: url, pointSize: pointSize)
        open.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.player.play()
    }

    private init(url: URL, pointSize: CGSize) {
        self.url = url
        player = AVPlayer(url: url)
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let fit = min(1, 720 / pointSize.width, screen.height * 0.7 / pointSize.height)
        let video = CGSize(width: max(pointSize.width * fit, 360), height: max(pointSize.height * fit, 200))
        super.init(contentRect: CGRect(origin: .zero, size: CGSize(width: video.width, height: video.height + 52)),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Screen Recording"
        isReleasedWhenClosed = false
        level = .floating

        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline

        let save = NSButton(title: "Save…", target: self, action: #selector(saveVideo))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyVideo))
        copy.keyEquivalent = "\r"
        contentView = ResultLayout.make(main: playerView, buttons: [save, copy])
    }

    @objc private func copyVideo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        Output.toast("Recording copied")
        close()
    }

    @objc private func saveVideo() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = url.lastPathComponent
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: url, to: target)
            close()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    override func close() {
        player.pause()
        super.close()
        VideoResultWindow.open.removeAll { $0 === self }
    }
}

private enum ResultLayout {
    static func make(main: NSView, buttons: [NSButton]) -> NSView {
        let content = NSView()
        let row = NSStackView(views: buttons)
        row.spacing = 8
        buttons.forEach { $0.bezelStyle = .rounded }
        main.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)
        content.addSubview(row)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            main.topAnchor.constraint(equalTo: content.topAnchor),
            row.topAnchor.constraint(equalTo: main.bottomAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
        return content
    }
}
