import AppKit
import ScreenCaptureKit
import SnipKit

/// What to capture, resolved against what is on screen right now.
struct Target {
    /// nil for a screen or region captured straight from the screen rect (`direct`), which skips looking up windows.
    let filter: SCContentFilter?
    /// The area in global screen points, top-left origin.
    let frame: CGRect
    let scale: CGFloat
    /// Display-local source rect for region captures; nil captures the whole window or display.
    let sourceRect: CGRect?
    let window: SCWindow?
    let label: String
    /// Global rect for SCScreenshotManager.captureImage(in:), the fastest way to grab a screen or region.
    var direct: CGRect? = nil
    /// A window to grab with CoreGraphics' window capture (see `LegacyCapture`), which skips ScreenCaptureKit's setup.
    var legacyWindow: CGWindowID? = nil

    /// Screen and region captures with no window in them come out opaque, so their PNGs skip the alpha channel.
    var opaque: Bool { window == nil && legacyWindow == nil }

    var pixelSize: CGSize { CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded()) }

    /// `stills: true` is for one-off images (shot, ocr): screens and regions then skip ScreenCaptureKit's
    /// window lookup, which costs more than the capture itself. Video and scrolling need the stream filter.
    static func resolve(_ args: inout ArgReader, stills: Bool = false) async throws -> Target {
        let app = try args.value("--app")
        let windowID = try args.value("--window")
        let region = try args.value("--region")
        let screen = try args.value("--screen")
        guard [app, windowID, region, screen].compactMap({ $0 }).count <= 1 else {
            throw CLIError("pick one target: --app, --window, --region or --screen")
        }
        // The direct path checks permission only if the capture fails: asking first costs more than the capture.
        if stills, app == nil, windowID == nil, #available(macOS 15.2, *) {
            return try direct(region: region, screen: screen)
        }
        try Permissions.requireScreenRecording()
        // Opens the WindowServer session that ScreenCaptureKit's window filters assume (and that keeps reading a
        // captured window's pixels fast). NSApplication used to do this as a side effect, at ten times the cost.
        _ = CGMainDisplayID()
        try Screens.requireAwake()
        if stills, LegacyCapture.available {
            if let id = windowID {
                guard let number = CGWindowID(id), let w = Windows.listed().first(where: { $0.id == number }) else {
                    throw CLIError("no on-screen window with id \(id). Run `snip windows`.")
                }
                return forListed(w)
            }
            if let app {
                guard let w = Windows.frontmostListed(of: app) else {
                    throw CLIError("no on-screen window for app \"\(app)\". Run `snip windows` to see what is open.")
                }
                return forListed(w)
            }
        }
        Trace.mark("permission")
        let content = try await Deadline.retrying("listing windows") {
            try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        }
        Trace.mark("shareable content")

        if let app {
            guard let window = Windows.frontmost(of: app, in: content) else {
                throw CLIError("no on-screen window for app \"\(app)\". Run `snip windows` to see what is open.")
            }
            return forWindow(window)
        }
        if let windowID {
            guard let id = UInt32(windowID), let window = content.windows.first(where: { $0.windowID == id }) else {
                throw CLIError("no on-screen window with id \(windowID). Run `snip windows`.")
            }
            return forWindow(window)
        }
        if let region {
            let v = try numbers(region, count: 4, what: "--region")
            let rect = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
            guard rect.width >= 1, rect.height >= 1,
                  let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
            else { throw CLIError("--region \(region) is not on any display") }
            let clipped = rect.intersection(display.frame)
            let local = clipped.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            return Target(filter: SCContentFilter(display: display, excludingWindows: []), frame: clipped,
                          scale: Screens.scale(of: display.displayID), sourceRect: local, window: nil, label: "region")
        }
        let displays = content.displays.sorted { a, b in
            (a.displayID == CGMainDisplayID() ? 0 : 1, a.frame.minX) < (b.displayID == CGMainDisplayID() ? 0 : 1, b.frame.minX)
        }
        let index = Int(screen ?? "1") ?? 0
        guard index >= 1, index <= displays.count else { throw CLIError("--screen wants 1…\(displays.count)") }
        let display = displays[index - 1]
        return Target(filter: SCContentFilter(display: display, excludingWindows: []), frame: display.frame,
                      scale: Screens.scale(of: display.displayID), sourceRect: nil, window: nil, label: "screen \(index)")
    }

    static func forWindow(_ window: SCWindow) -> Target {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return Target(filter: SCContentFilter(desktopIndependentWindow: window), frame: window.frame,
                      scale: Screens.scale(at: center), sourceRect: nil, window: window,
                      label: window.owningApplication?.applicationName ?? "window")
    }

    func configuration(cursor: Bool = false) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        if let sourceRect { config.sourceRect = sourceRect }
        config.width = Int(pixelSize.width)
        config.height = Int(pixelSize.height)
        config.showsCursor = cursor
        config.captureResolution = .best
        return config
    }

    func capture() async throws -> CGImage {
        if let legacyWindow {
            if let image = LegacyCapture.window(legacyWindow) { return image }
            // The old call is gone or refused: look the window up the ScreenCaptureKit way and use that.
            let content = try await Deadline.retrying("listing windows") {
                try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            }
            guard let window = content.windows.first(where: { $0.windowID == legacyWindow }) else {
                throw CLIError("the window closed before it could be captured")
            }
            return try await Target.forWindow(window).capture()
        }
        do {
            return try await Deadline.retrying("the screen capture") { [self] in
                if let direct, #available(macOS 15.2, *) {
                    return try await SCScreenshotManager.captureImage(in: direct)
                }
                return try await SCScreenshotManager.captureImage(contentFilter: filter!, configuration: configuration())
            }
        } catch {
            if direct != nil { try Permissions.requireScreenRecording() }
            try Screens.requireAwake()
            throw error
        }
    }

    /// Pixels per point of a captured image. Direct captures read it off the image instead of asking the display.
    func scale(of image: CGImage) -> CGFloat {
        direct == nil && legacyWindow == nil ? scale : CGFloat(image.width) / frame.width
    }

    private static func forListed(_ w: Windows.Listed) -> Target {
        Target(filter: nil, frame: w.frame, scale: 0, sourceRect: nil, window: nil, label: w.owner, legacyWindow: w.id)
    }

    /// Screen or region straight from CoreGraphics' display list, no ScreenCaptureKit lookup.
    private static func direct(region: String?, screen: String?) throws -> Target {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        if count == 0 { try Screens.requireAwake() }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        if let region {
            let v = try numbers(region, count: 4, what: "--region")
            let rect = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
            guard rect.width >= 1, rect.height >= 1,
                  let id = ids.first(where: { CGDisplayBounds($0).contains(CGPoint(x: rect.midX, y: rect.midY)) })
            else { throw CLIError("--region \(region) is not on any display") }
            let clipped = rect.intersection(CGDisplayBounds(id))
            return Target(filter: nil, frame: clipped, scale: 0, sourceRect: nil, window: nil, label: "region", direct: clipped)
        }
        let displays = ids.sorted { a, b in
            (a == CGMainDisplayID() ? 0 : 1, CGDisplayBounds(a).minX) < (b == CGMainDisplayID() ? 0 : 1, CGDisplayBounds(b).minX)
        }
        let index = Int(screen ?? "1") ?? 0
        guard index >= 1, index <= displays.count else { throw CLIError("--screen wants 1…\(displays.count)") }
        let id = displays[index - 1]
        return Target(filter: nil, frame: CGDisplayBounds(id), scale: 0, sourceRect: nil, window: nil,
                      label: "screen \(index)", direct: CGDisplayBounds(id))
    }
}

/// ScreenCaptureKit occasionally never answers a request (seen when the Mac is overloaded), which would leave
/// snip waiting forever. Give each request a deadline and one more try, then fail with a clear message.
enum Deadline {
    static func retrying<T>(_ what: String, seconds: [Double] = [4, 8], _ body: @escaping () async throws -> T) async throws -> T {
        for (attempt, limit) in seconds.enumerated() {
            do {
                return try await run(limit, body)
            } catch is TimedOut where attempt < seconds.count - 1 {
                Trace.mark("\(what) timed out, retrying")
            } catch is TimedOut {
                throw CLIError("\(what) did not respond (ScreenCaptureKit). Try again; if it keeps happening, restart the Mac's screen capture service with `killall replayd`.")
            }
        }
        fatalError()
    }

    private struct TimedOut: Error {}

    private final class Once: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    /// Not a task group: a group waits for every child, and a request that never returns would block it too.
    private static func run<T>(_ seconds: Double, _ body: @escaping () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let once = Once()
            Task {
                do {
                    let value = try await body()
                    if once.claim() { continuation.resume(returning: value) }
                } catch {
                    if once.claim() { continuation.resume(throwing: error) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                if once.claim() { continuation.resume(throwing: TimedOut()) }
            }
        }
    }
}

enum Screens {
    /// A locked screen or sleeping display has nothing to capture, and macOS reports it with obscure errors.
    static func requireAwake() throws {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        if (session["CGSSessionScreenIsLocked"] as? Bool) == true || CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            throw CLIError("the screen is locked or the display is asleep, so there is nothing to capture. Ask the user to unlock the Mac.")
        }
    }

    /// Global top-left points → the backing scale of the display under them.
    static func scale(at point: CGPoint) -> CGFloat {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(point, 1, &id, &count)
        return count > 0 ? scale(of: id) : (NSScreen.main?.backingScaleFactor ?? 2)
    }

    static func scale(of id: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 else { return 2 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

/// CGWindowListCreateImage: Apple hid it from the macOS 15 SDK in favor of ScreenCaptureKit, but it still ships,
/// and for one window from a fresh process it is several times faster (ScreenCaptureKit sets up a capture
/// session for every new process). Looked up at runtime; when it's missing or returns nothing, snip falls back.
enum LegacyCapture {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImage? = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage")
        .map { unsafeBitCast($0, to: CreateImage.self) }

    static var available: Bool { createImage != nil && ProcessInfo.processInfo.environment["SNIP_NO_LEGACY"] == nil }

    static func window(_ id: CGWindowID) -> CGImage? {
        guard available else { return nil }
        // kCGWindowListOptionIncludingWindow; kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
        return createImage?(.null, 1 << 3, id, (1 << 0) | (1 << 3))?.takeRetainedValue()
    }
}

enum Windows {
    /// A window from CoreGraphics' window list: no ScreenCaptureKit round trip.
    struct Listed {
        let id: CGWindowID
        let frame: CGRect
        let owner: String
        let pid: pid_t
        var bundle: String { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "" }
    }

    /// Normal-layer windows that are big enough to matter, front to back.
    static func listed() -> [Listed] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0, let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary, let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= 40, frame.height >= 40, let pid = w[kCGWindowOwnerPID as String] as? pid_t
            else { return nil }
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            return Listed(id: id, frame: frame, owner: owner, pid: pid)
        }
    }

    static func frontmostListed(of app: String) -> Listed? {
        let needle = app.lowercased()
        let windows = listed()
        return windows.first { $0.owner.lowercased() == needle }
            ?? windows.first { $0.bundle.lowercased() == needle }
            ?? windows.first { $0.owner.lowercased().contains(needle) }
    }

    /// Normal-layer windows that are big enough to matter, front to back.
    static func visible(in content: SCShareableContent) -> [SCWindow] {
        let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? UInt32 }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return content.windows
            .filter { $0.windowLayer == 0 && $0.frame.width >= 40 && $0.frame.height >= 40 && $0.owningApplication != nil }
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
    }

    static func frontmost(of app: String, in content: SCShareableContent) -> SCWindow? {
        let needle = app.lowercased()
        let windows = visible(in: content)
        func name(_ w: SCWindow) -> String { w.owningApplication?.applicationName.lowercased() ?? "" }
        func bundle(_ w: SCWindow) -> String { w.owningApplication?.bundleIdentifier.lowercased() ?? "" }
        return windows.first { name($0) == needle || bundle($0) == needle }
            ?? windows.first { name($0).contains(needle) }
    }
}

enum Permissions {
    static func requireScreenRecording() throws {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw CLIError("""
            Screen Recording permission is off for the app running snip (\(hostApp)).
            Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording, restart \(hostApp), then try again.
            """)
        }
    }

    static func requireAccessibility() throws {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) else {
            throw CLIError("""
            `snip scroll` sends scroll events, which needs Accessibility permission for the app running snip (\(hostApp)).
            Turn it on in System Settings > Privacy & Security > Accessibility, then try again.
            """)
        }
    }

    /// The terminal or agent app that owns this process, for permission messages.
    static var hostApp: String {
        var pid = getppid()
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName { return name }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, info.kp_eproc.e_ppid > 1 else { break }
            pid = info.kp_eproc.e_ppid
        }
        return "your terminal"
    }
}

enum ImageFile {
    /// PNG with the display's DPI, so it opens at its real size. `opaque` drops the alpha channel.
    static func writePNG(_ image: CGImage, scale: CGFloat, opaque: Bool? = nil, to url: URL) throws {
        let data = try PNGEncoder.encode(image, scale: scale, opaque: opaque)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    static func read(_ path: String) throws -> (CGImage, CGFloat) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CLIError("can't read image \(path)") }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        // Retina screenshots say 144 dpi. Many tools write no DPI at all, so a wide image counts as Retina.
        if let dpi = props?[kCGImagePropertyDPIWidth] as? Double, dpi > 72 { return (image, CGFloat(dpi / 72).rounded()) }
        return (image, image.width >= 2400 ? 2 : 1)
    }
}
