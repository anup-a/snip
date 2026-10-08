import AppKit

/// `snip pin`: floats an image above every window so the agent can show the user something.
/// Drag to move, scroll to zoom, double-click or Esc to close.
enum Pin {
    static func run(_ argv: [String]) throws {
        var args = ArgReader(argv)
        let json = args.flag("--json")
        let foreground = args.flag("--foreground")
        let seconds = try args.value("--seconds").flatMap(Double.init)
        guard let path = args.positional() else { throw CLIError("pin needs an image: snip pin IMAGE") }
        try args.finish()
        let (image, scale) = try ImageFile.read(path)
        let full = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path

        guard foreground else {
            // Return to the agent right away; the pin lives in its own process until the user closes it.
            var child = ["pin", "--foreground", full]
            if let seconds { child += ["--seconds", String(seconds)] }
            let pid = try spawnDetached(child)
            report(["path": full, "pid": Int(pid)], json: json)
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, screen.width * 0.6 / size.width, screen.height * 0.7 / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        let frame = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        let window = PinPanel(image: image, frame: frame)
        window.orderFrontRegardless()
        window.makeKey()
        if let seconds { DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) } }
        app.run()
    }

    static func spawnDetached(_ args: [String]) throws -> pid_t {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        for fd: Int32 in [0, 1, 2] { posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0) }
        let argv = ([exe] + args).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, exe, &actions, &attr, argv, environ)
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attr)
        guard status == 0 else { throw CLIError("could not open the pin (error \(status))") }
        return pid
    }
}

private final class PinPanel: NSPanel {
    private let pointSize: CGSize
    private var zoom: CGFloat = 1

    init(image: CGImage, frame: CGRect) {
        pointSize = frame.size
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PinContent(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        view.layer?.borderColor = NSColor(srgbRed: 0x33 / 255, green: 0x70 / 255, blue: 0xFF / 255, alpha: 0.6).cgColor
        view.layer?.borderWidth = 1
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.2), 5)
        let top = frame.maxY
        let size = CGSize(width: pointSize.width * zoom, height: pointSize.height * zoom)
        setFrame(CGRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    var currentZoom: CGFloat { zoom }
}

private final class PinContent: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { exit(0) }
        window?.makeKey()
        window?.makeFirstResponder(self)
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let pin = window as? PinPanel else { return }
        pin.setZoom(pin.currentZoom * (1 + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { exit(0) }
        super.keyDown(with: event)
    }
}
