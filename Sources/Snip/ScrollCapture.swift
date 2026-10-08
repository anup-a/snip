import AppKit
import SnipKit
import ScreenCaptureKit

/// Scrolling screenshot: the user scrolls inside the region and Snip stitches the frames into one tall image.
final class ScrollCapture: LiveCapture {
    private let region: CGRect
    private let screen: NSScreen
    private let scale: CGFloat
    private let stitcher = Stitcher()
    private let shade: RegionShade
    private var bar: LiveBar!
    private var preview: ScrollPreview?
    private let status = LiveBar.label("Scroll slowly to capture")
    private var loop: Task<Void, Never>?
    private var ended = false
    private let wheel = WheelWatch()

    static func start(region: CGRect, screen: NSScreen) {
        let capture = ScrollCapture(region: region, screen: screen)
        Live.current = capture
        capture.run()
    }

    private init(region: CGRect, screen: NSScreen) {
        self.region = region
        self.screen = screen
        scale = screen.backingScaleFactor
        shade = RegionShade(region: region, screen: screen, border: selectionBlue)
        let cancel = IconButton(symbol: "xmark", tip: "Cancel", tint: cancelRed) { [weak self] in self?.cancel() }
        let done = IconButton(symbol: "checkmark", tip: "Done (⌘⇧A)", tint: confirmGreen) { [weak self] in self?.finish() }
        bar = LiveBar(views: [status, cancel, done], region: region, screen: screen)
        preview = ScrollPreview(region: region, screen: screen)
        shade.orderFrontRegardless()
        preview?.orderFrontRegardless()
        bar.orderFrontRegardless()
    }

    private func run() {
        let region = region, screen = screen, scale = scale, stitcher = stitcher, wheel = wheel
        loop = Task.detached { [weak self] in
            do {
                let (filter, _) = try await LiveSource.filter(for: screen)
                let config = SCStreamConfiguration()
                config.sourceRect = LiveSource.sourceRect(region, on: screen)
                config.width = Int((region.width * scale).rounded())
                config.height = Int((region.height * scale).rounded())
                config.showsCursor = false
                config.captureResolution = .best
                while !Task.isCancelled {
                    let quietBefore = wheel.isQuiet
                    let frame = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    if Task.isCancelled { break }
                    // No wheel events around this frame: anything that changed is animating in place.
                    switch stitcher.add(frame, still: quietBefore && wheel.isQuiet) {
                    case .added:
                        let thumb = stitcher.compose(width: 300)
                        let height = stitcher.height
                        await MainActor.run { self?.update(thumb: thumb, pixelHeight: height) }
                    case .lost:
                        await MainActor.run { self?.status.stringValue = "Lost track, scroll back a little" }
                    case .unchanged:
                        break
                    }
                    if stitcher.isFull {
                        await MainActor.run { self?.finish() }
                        return
                    }
                    await Task.yield()
                }
            } catch is CancellationError {
            } catch {
                NSLog("Snip scrolling capture failed: \(error)")
                await MainActor.run {
                    Output.toast("Scrolling capture failed")
                    self?.cancel()
                }
            }
        }
    }

    private func update(thumb: CGImage?, pixelHeight: Int) {
        if let thumb { preview?.show(thumb) }
        status.stringValue = "\(Int(region.width * scale)) × \(pixelHeight)"
    }

    func finish() {
        guard !ended else { return }
        ended = true
        let loop = loop
        loop?.cancel()
        Task { @MainActor in
            await loop?.value
            tearDown()
            guard let image = stitcher.compose() else { return }
            let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            Output.copyImage(image, pointSize: size)
            ImageResultWindow.show(image, pointSize: size)
        }
    }

    private func cancel() {
        guard !ended else { return }
        ended = true
        loop?.cancel()
        tearDown()
    }

    private func tearDown() {
        wheel.stop()
        shade.orderOut(nil)
        bar.orderOut(nil)
        preview?.orderOut(nil)
        if Live.current === self { Live.current = nil }
    }
}

/// Notes when the user last scrolled anywhere, so frames taken while nobody scrolls can teach the
/// stitcher what animates by itself. Until the first wheel event arrives it claims nothing.
private final class WheelWatch {
    private let lock = NSLock()
    private var last: Date?
    private var monitor: Any?

    init() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.last = Date() }
        }
    }

    /// True once scrolling has been seen and nothing (momentum included) has scrolled for a moment.
    var isQuiet: Bool {
        lock.withLock { last.map { Date().timeIntervalSince($0) > 0.4 } ?? false }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// The growing long image, shown beside the region while the user scrolls.
private final class ScrollPreview: NSPanel {
    private let imageView = NSImageView()

    init?(region: CGRect, screen: NSScreen) {
        let width: CGFloat = 150
        let visible = screen.visibleFrame
        let height = min(region.height, visible.height)
        var x = region.maxX + 12
        if x + width > visible.maxX { x = region.minX - 12 - width }
        guard x >= visible.minX else { return nil }
        let y = min(max(region.maxY - height, visible.minY), visible.maxY - height)
        super.init(contentRect: CGRect(x: x, y: y, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let box = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.white.cgColor
        box.layer?.cornerRadius = 8
        box.layer?.masksToBounds = true
        imageView.frame = box.bounds.insetBy(dx: 6, dy: 6)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignTop
        box.addSubview(imageView)
        contentView = box
    }

    func show(_ image: CGImage) {
        imageView.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }
}
