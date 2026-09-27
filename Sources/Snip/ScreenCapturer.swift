import AppKit
import ScreenCaptureKit

struct ScreenShot {
    let screen: NSScreen
    let image: CGImage
    let scale: CGFloat
}

enum ScreenCapturer {
    /// Freezes every display into an image before the overlay appears.
    static func captureAllScreens() async throws -> [ScreenShot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var shots: [ScreenShot] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            shots.append(ScreenShot(screen: screen, image: image, scale: scale))
        }
        return shots
    }

    /// On-screen window frames, front to back, in Cocoa global coordinates.
    static func windowRects() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = Int(getpid())
        var rects: [CGRect] = []
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int, (0...25).contains(layer),
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 20, bounds.height >= 20 else { continue }
            if (window[kCGWindowAlpha as String] as? Double ?? 1) <= 0.01 { continue }
            if window[kCGWindowOwnerPID as String] as? Int == ownPID, layer != 3 { continue }
            // Skip transparent full-screen shields (Dock, Notification Centre, WindowServer) above normal windows.
            if layer > 0, NSScreen.screens.contains(where: { bounds.width >= $0.frame.width * 0.95 && bounds.height >= $0.frame.height * 0.9 }) {
                continue
            }
            let cocoaY = primary.frame.height - bounds.maxY
            rects.append(CGRect(x: bounds.minX, y: cocoaY, width: bounds.width, height: bounds.height))
        }
        return rects
    }
}
