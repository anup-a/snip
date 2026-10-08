import AppKit
import SnipKit
import AVFoundation
import ScreenCaptureKit

/// Records a region of the screen to an MP4, with pause, until the user stops it.
final class ScreenRecorder: LiveCapture {
    private let region: CGRect
    private let screen: NSScreen
    private let shade: RegionShade
    private var bar: LiveBar!
    private let clock = LiveBar.label("00:00", monospaced: true)
    private var pauseButton: IconButton!
    private let writer: RegionWriter
    private var stream: SCStream?
    private var ticker: Timer?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var ended = false

    static func start(region: CGRect, screen: NSScreen) {
        let recorder = ScreenRecorder(region: region, screen: screen)
        Live.current = recorder
        recorder.run()
    }

    private init(region: CGRect, screen: NSScreen) {
        self.region = region
        self.screen = screen
        let scale = screen.backingScaleFactor
        // H.264 wants even dimensions.
        let pixels = CGSize(width: (Int(region.width * scale) / 2) * 2, height: (Int(region.height * scale) / 2) * 2)
        writer = RegionWriter(url: ScreenRecorder.newFileURL(), pixelSize: pixels)
        shade = RegionShade(region: region, screen: screen, border: cancelRed)

        let dot = NSImageView(image: NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))!)
        dot.contentTintColor = cancelRed
        pauseButton = IconButton(symbol: "pause.fill", tip: "Pause") { [weak self] in self?.togglePause() }
        let stop = IconButton(symbol: "stop.fill", tip: "Stop (⌘⇧A)", tint: cancelRed) { [weak self] in self?.finish() }
        let discard = IconButton(symbol: "xmark", tip: "Discard") { [weak self] in self?.discard() }
        bar = LiveBar(views: [dot, clock, pauseButton, stop, discard], region: region, screen: screen)
        shade.orderFrontRegardless()
        bar.orderFrontRegardless()
    }

    private static func newFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Screen Recording \(formatter.string(from: Date())).mp4")
    }

    private func run() {
        Task { @MainActor in
            do {
                let (filter, _) = try await LiveSource.filter(for: screen)
                let config = SCStreamConfiguration()
                config.sourceRect = LiveSource.sourceRect(region, on: screen)
                config.width = Int(writer.pixelSize.width)
                config.height = Int(writer.pixelSize.height)
                config.showsCursor = true
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.colorSpaceName = CGColorSpace.sRGB
                config.queueDepth = 6
                try writer.prepare()
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
                try await stream.startCapture()
                self.stream = stream
                startedAt = Date()
                ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            } catch {
                NSLog("Snip recording failed to start: \(error)")
                Output.toast("Recording failed to start")
                discard()
            }
        }
    }

    private var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        let pausedNow = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
        return Date().timeIntervalSince(startedAt) - pausedTotal - pausedNow
    }

    private func tick() {
        let seconds = Int(elapsed)
        clock.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func togglePause() {
        guard stream != nil, !ended else { return }
        if let pausedAt {
            pausedTotal += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
            writer.setPaused(false)
            pauseButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
            pauseButton.toolTip = "Pause"
        } else {
            pausedAt = Date()
            writer.setPaused(true)
            pauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Resume")?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
            pauseButton.toolTip = "Resume"
        }
    }

    func finish() {
        guard !ended else { return }
        ended = true
        let pointSize = CGSize(width: writer.pixelSize.width / screen.backingScaleFactor,
                               height: writer.pixelSize.height / screen.backingScaleFactor)
        Task { @MainActor in
            try? await stream?.stopCapture()
            tearDown()
            if let url = await writer.finish() {
                VideoResultWindow.show(url, pointSize: pointSize)
            } else {
                Output.toast("Nothing was recorded")
            }
        }
    }

    private func discard() {
        guard !ended else { tearDown(); return }
        ended = true
        Task { @MainActor in
            try? await stream?.stopCapture()
            tearDown()
            if let url = await writer.finish() { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func tearDown() {
        ticker?.invalidate()
        shade.orderOut(nil)
        bar.orderOut(nil)
        if Live.current === self { Live.current = nil }
    }
}
