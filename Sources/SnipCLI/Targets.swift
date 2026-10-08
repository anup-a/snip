import AppKit
import ScreenCaptureKit

/// What to capture, resolved against what is on screen right now.
struct Target {
    let filter: SCContentFilter
    /// The area in global screen points, top-left origin.
    let frame: CGRect
    let scale: CGFloat
    /// Display-local source rect for region captures; nil captures the whole window or display.
    let sourceRect: CGRect?
    let window: SCWindow?
    let label: String

    var pixelSize: CGSize { CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded()) }

    static func resolve(_ args: inout ArgReader) async throws -> Target {
        let app = try args.value("--app")
        let windowID = try args.value("--window")
        let region = try args.value("--region")
        let screen = try args.value("--screen")
        guard [app, windowID, region, screen].compactMap({ $0 }).count <= 1 else {
            throw CLIError("pick one target: --app, --window, --region or --screen")
        }
        try Permissions.requireScreenRecording()
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)

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
        try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration())
    }
}

enum Screens {
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

enum Windows {
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
    /// PNG with the display's DPI, so it opens at its real size.
    static func writePNG(_ image: CGImage, scale: CGFloat, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CLIError("could not encode PNG") }
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
