import AppKit
import UniformTypeIdentifiers
import Vision

enum Output {
    static func pngData(_ image: CGImage, pointSize: CGSize) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = pointSize // keeps Retina DPI metadata
        return rep.representation(using: .png, properties: [:])
    }

    static func copyImage(_ image: CGImage, pointSize: CGSize) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = pointSize
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) { pasteboard.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }

    static func copyString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func save(_ image: CGImage, pointSize: CGSize) {
        NSApp.activate(ignoringOtherApps: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot \(formatter.string(from: Date())).png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url, let data = pngData(image, pointSize: pointSize) else { return }
        do {
            try data.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func recognizeText(in image: CGImage) {
        let request = VNRecognizeTextRequest { request, _ in
            let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                if text.isEmpty {
                    toast("No text found")
                } else {
                    copyString(text)
                    TextResultWindow.show(text)
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: image).perform([request])
        }
    }

    private static var toastWindow: NSWindow?

    static func toast(_ message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        let size = label.fittingSize
        let box = CGSize(width: size.width + 28, height: size.height + 16)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let frame = CGRect(x: screen.frame.midX - box.width / 2, y: screen.frame.minY + 120, width: box.width, height: box.height)

        toastWindow?.orderOut(nil)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = NSView(frame: CGRect(origin: .zero, size: box))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        content.layer?.cornerRadius = box.height / 2
        label.frame = CGRect(x: 14, y: 8, width: size.width, height: size.height)
        content.addSubview(label)
        window.contentView = content
        window.orderFrontRegardless()
        toastWindow = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; window.animator().alphaValue = 0 }) {
                window.orderOut(nil)
                if toastWindow === window { toastWindow = nil }
            }
        }
    }
}

/// Shows OCR output, editable, already on the clipboard.
final class TextResultWindow: NSWindow {
    private static var open: [TextResultWindow] = []

    static func show(_ text: String) {
        let window = TextResultWindow(text: text)
        open.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private let textView: NSTextView

    private init(text: String) {
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        super.init(contentRect: CGRect(x: 0, y: 0, width: 460, height: 340),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Extracted Text (copied)"
        isReleasedWhenClosed = false
        level = .floating
        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = CGSize(width: 10, height: 10)

        let copy = NSButton(title: "Copy", target: nil, action: nil)
        copy.bezelStyle = .rounded
        copy.keyEquivalent = "\r"
        copy.target = self
        copy.action = #selector(copyText)

        let content = NSView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        copy.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        content.addSubview(copy)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            copy.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            copy.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            copy.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
        contentView = content
    }

    @objc private func copyText() {
        Output.copyString(textView.string)
        close()
    }

    override func close() {
        super.close()
        TextResultWindow.open.removeAll { $0 === self }
    }
}
