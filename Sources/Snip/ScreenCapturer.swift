import AppKit
import SnipKit
import ImageIO
import ScreenCaptureKit

struct ScreenShot {
    let screen: NSScreen
    let image: CGImage
    let scale: CGFloat
    /// Overlay frame in Cocoa points. Live captures use the display frame; demo renders use the scene.
    let frame: CGRect
}

enum ScreenCapturer {
    /// Freezes every display into an image before the overlay appears.
    static func captureAllScreens() async throws -> [ScreenShot] {
        if let demo = demoShot() { return [demo] }
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
            shots.append(ScreenShot(screen: screen, image: image, scale: scale, frame: screen.frame))
        }
        return shots
    }

    // Demo mode for marketing shots: SNIP_DEMO_IMAGE replaces the display capture and
    // SNIP_DEMO_WINDOWS ("x,y,w,h;..." in top-left points) replaces the hover targets.
    // Scenes are 2× PNGs of a 1440×900 point desktop, so the canvas does not follow the live display.
    private static var demoEnv: [String: String] { ProcessInfo.processInfo.environment }
    private static let demoScale: CGFloat = 2

    static func demoShot() -> ScreenShot? {
        guard let path = demoEnv["SNIP_DEMO_IMAGE"], let screen = NSScreen.main ?? NSScreen.screens.first,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let frame = CGRect(x: 0, y: 0, width: CGFloat(image.width) / demoScale, height: CGFloat(image.height) / demoScale)
        return ScreenShot(screen: screen, image: image, scale: demoScale, frame: frame)
    }

    /// On-screen window frames, front to back, in Cocoa global coordinates.
    static func windowRects() -> [CGRect] {
        if let spec = demoEnv["SNIP_DEMO_WINDOWS"], let canvas = demoShot()?.frame {
            return spec.split(separator: ";").compactMap { part in
                let v = part.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard v.count == 4 else { return nil }
                return CGRect(x: v[0], y: canvas.height - v[1] - v[3], width: v[2], height: v[3])
            }
        }
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
