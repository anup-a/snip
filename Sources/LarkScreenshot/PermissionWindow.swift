import AppKit

/// Walks the user through granting Screen Recording, then relaunches Lark Screenshot so the grant takes effect.
final class PermissionWindow: NSWindow {
    private static var shared: PermissionWindow?

    static func show() {
        let window = shared ?? PermissionWindow()
        shared = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.startPolling()
    }

    private let statusLabel = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private let primaryButton = NSButton(title: "Open System Settings", target: nil, action: nil)
    private let relaunchButton = NSButton(title: "Relaunch", target: nil, action: nil)
    private var timer: Timer?

    private init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 480, height: 400), styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = "Set Up Lark Screenshot"
        isReleasedWhenClosed = false
        level = .floating

        let icon = NSImageView(image: NSImage(systemSymbolName: "scissors.circle.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 44, weight: .regular))!)
        icon.contentTintColor = larkBlue

        let heading = NSTextField(labelWithString: "Allow Lark Screenshot to capture your screen")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)

        let intro = NSTextField(wrappingLabelWithString:
            "macOS requires Screen Recording permission before any app can take screenshots. Lark Screenshot only captures when you press ⌃⇧A and never records video.")
        intro.textColor = .secondaryLabelColor

        let steps = NSStackView(views: [
            step(1, "Click **Open System Settings** below."),
            step(2, "Under **Screen & System Audio Recording**, turn on the switch next to **Lark Screenshot**. If Lark Screenshot isn't listed, click **+** and choose Lark Screenshot from Applications."),
            step(3, "Confirm with your password or Touch ID if asked."),
            step(4, "Come back here and click **Relaunch**. macOS applies the permission after a relaunch."),
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 10

        statusIcon.imageScaling = .scaleProportionallyUpOrDown
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusIcon.widthAnchor.constraint(equalToConstant: 16),
            statusIcon.heightAnchor.constraint(equalToConstant: 16),
        ])
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let status = NSStackView(views: [statusIcon, statusLabel])
        status.spacing = 6

        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        primaryButton.action = #selector(openSettings)
        relaunchButton.bezelStyle = .rounded
        relaunchButton.target = self
        relaunchButton.action = #selector(relaunch)
        let buttons = NSStackView(views: [relaunchButton, primaryButton])
        buttons.spacing = 10

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bottom = NSStackView(views: [spacer, buttons])

        let root = NSStackView(views: [icon, heading, intro, steps, status, bottom])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.setCustomSpacing(8, after: heading)
        root.setCustomSpacing(20, after: steps)
        root.setCustomSpacing(16, after: status)
        root.edgeInsets = NSEdgeInsets(top: 22, left: 26, bottom: 20, right: 26)
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 480),
            intro.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -52),
            steps.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -52),
            bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -52),
        ])
        contentView = content
        updateStatus()
    }

    private func step(_ number: Int, _ markdown: String) -> NSView {
        let badge = StepBadge(number: number)

        let text = NSTextField(wrappingLabelWithString: "")
        let attributed = (try? NSMutableAttributedString(markdown: markdown)) ?? NSMutableAttributedString(string: markdown)
        let full = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        attributed.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
            let bold = (value as? UInt).map { InlinePresentationIntent(rawValue: $0).contains(.stronglyEmphasized) } ?? false
            attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: bold ? .semibold : .regular), range: range)
        }
        text.attributedStringValue = attributed

        let row = NSStackView(views: [badge, text])
        row.alignment = .top
        row.spacing = 10
        return row
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatus() }
    }

    private func updateStatus() {
        let granted = CGPreflightScreenCaptureAccess()
        statusIcon.image = NSImage(systemSymbolName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                   accessibilityDescription: nil)
        statusIcon.contentTintColor = granted ? .systemGreen : .systemOrange
        statusLabel.stringValue = granted ? "Access granted. Press ⌃⇧A to take a screenshot." : "Waiting for permission…"
        if granted {
            primaryButton.title = "Done"
            primaryButton.action = #selector(finish)
            relaunchButton.isHidden = true
        }
    }

    @objc private func openSettings() {
        // Registers Lark Screenshot in the Screen Recording list (and shows the system prompt the first time).
        CGRequestScreenCaptureAccess()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    @objc private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func finish() { close() }

    override func close() {
        timer?.invalidate()
        timer = nil
        super.close()
    }
}

/// A filled circle with a centered step number.
private final class StepBadge: NSView {
    private let number: Int

    init(number: Int) {
        self.number = number
        super.init(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 20) }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let circle = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        NSBezierPath(ovalIn: circle).fill(larkBlue)
        let text = "\(number)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2), withAttributes: attrs)
    }
}
