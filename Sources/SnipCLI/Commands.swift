import AppKit
import AVFoundation
import CoreImage.CIFilterBuiltins
import ScreenCaptureKit
import SnipKit
import Vision

enum Commands {
    // MARK: shot

    static func shot(_ argv: [String]) async throws {
        var args = ArgReader(argv)
        let json = args.flag("--json")
        let out = outputURL(try args.value("-o", "--out"), ext: "png", prefix: "shot")
        let target = try await Target.resolve(&args)
        try args.finish()
        let image = try await target.capture()
        try ImageFile.writePNG(image, scale: target.scale, to: out)
        report(["path": out.path, "width": image.width, "height": image.height, "scale": target.scale, "target": target.label], json: json)
    }

    // MARK: scroll

    static func scroll(_ argv: [String]) async throws {
        var args = ArgReader(argv)
        let json = args.flag("--json")
        let out = outputURL(try args.value("-o", "--out"), ext: "png", prefix: "scroll")
        let at = try args.value("--at").map { try numbers($0, count: 2, what: "--at") }
        let maxHeight = try args.value("--max").flatMap(Int.init) ?? Stitcher.maxHeight
        let fromTop = !args.flag("--from-here")
        let target = try await Target.resolve(&args)
        try args.finish()
        guard target.sourceRect != nil || target.window != nil else {
            throw CLIError("scroll needs --app, --window or --region (the thing to scroll)")
        }
        try Permissions.requireAccessibility()

        // Scroll events go to whatever is under the pointer, so bring the window forward and park the pointer on it.
        if let pid = target.window?.owningApplication?.processID {
            NSRunningApplication(processIdentifier: pid)?.activate()
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        let point = at.map { CGPoint(x: target.frame.minX + $0[0], y: target.frame.minY + $0[1]) }
            ?? CGPoint(x: target.frame.midX, y: target.frame.minY + target.frame.height * 0.55)
        let savedMouse = CGEvent(source: nil)?.location ?? point
        let events = ScrollEvents(at: point)
        defer { events.restoreMouse(to: savedMouse) }
        events.movePointer()

        if fromTop {
            var last: [UInt8] = []
            for _ in 0..<30 {
                events.scroll(points: -4000)
                try await Task.sleep(nanoseconds: 180_000_000)
                let rows = Stitcher.rowSignatures(try await target.capture())
                if Stitcher.isSameView(rows, last) { break }
                last = rows
            }
        }

        let stitcher = Stitcher()
        _ = stitcher.add(try await target.capture())
        // Two frames with no scrolling in between show what animates by itself (video, spinners).
        for _ in 0..<2 {
            try await Task.sleep(nanoseconds: 250_000_000)
            _ = stitcher.add(try await target.capture(), still: true)
        }
        var step = target.frame.height * 0.45
        // Ctrl-C (or an agent's timeout sending SIGINT/SIGTERM) keeps what was captured so far.
        let interrupted = Background.interruptFlag()
        var still = 0, lost = 0
        scrolling: while stitcher.height < maxHeight && !stitcher.isFull && !interrupted.isSet {
            events.scroll(points: step)
            try await Task.sleep(nanoseconds: 350_000_000)
            switch stitcher.add(try await target.capture()) {
            case .added:
                still = 0
            case .unchanged:
                still += 1
                if still >= 2 { break scrolling } // reached the end
            case .lost:
                // Moved further than the overlap allows (big sticky headers): back up and take smaller steps.
                lost += 1
                if lost > 6 { break scrolling }
                events.scroll(points: -step * 0.5)
                step *= 0.6
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        guard let image = stitcher.compose() else { throw CLIError("nothing captured") }
        try ImageFile.writePNG(image, scale: target.scale, to: out)
        report(["path": out.path, "width": image.width, "height": image.height, "scale": target.scale, "target": target.label], json: json)
    }

    // MARK: record

    static func record(_ argv: [String]) async throws {
        var args = ArgReader(argv)
        if args.flag("--background", "--detach") {
            try Background.spawnRecording(args.rest)
            return
        }
        let json = args.flag("--json")
        let quiet = args.flag("--quiet")
        let cursor = !args.flag("--no-cursor")
        let out = outputURL(try args.value("-o", "--out"), ext: "mp4", prefix: "recording")
        let seconds = try args.value("--seconds").flatMap(Double.init)
        let target = try await Target.resolve(&args)
        try args.finish()
        if FileManager.default.fileExists(atPath: out.path) { try FileManager.default.removeItem(at: out) }
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

        let even = CGSize(width: (Int(target.pixelSize.width) / 2) * 2, height: (Int(target.pixelSize.height) / 2) * 2)
        let writer = RegionWriter(url: out, pixelSize: even)
        try writer.prepare()
        let config = target.configuration(cursor: cursor)
        config.width = Int(even.width)
        config.height = Int(even.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 6
        let stream = SCStream(filter: target.filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        try await stream.startCapture()
        try Background.writeState(path: out.path)
        if !quiet && !json { FileHandle.standardError.write("Recording \(target.label). Stop with Ctrl-C or `snip stop`.\n".data(using: .utf8)!) }

        await Background.waitForStop(seconds: seconds)
        try? await stream.stopCapture()
        Background.clearState()
        guard let url = await writer.finish() else { throw CLIError("nothing was recorded") }
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        report(["path": url.path, "width": Int(even.width), "height": Int(even.height),
                "seconds": Double(String(format: "%.1f", duration))!, "target": target.label], json: json)
    }

    static func stop(_ argv: [String]) async throws {
        var args = ArgReader(argv)
        let json = args.flag("--json")
        try args.finish()
        guard let (pid, path) = Background.readState() else { throw CLIError("no recording is running") }
        kill(pid, SIGINT)
        for _ in 0..<150 where kill(pid, 0) == 0 { try await Task.sleep(nanoseconds: 100_000_000) }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { throw CLIError("the recording did not finish writing \(path)") }
        let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        report(["path": path, "seconds": Double(String(format: "%.1f", duration))!], json: json)
    }

    // MARK: mark

    static func mark(_ argv: [String]) throws {
        var args = ArgReader(argv)
        let json = args.flag("--json")
        let outPath = try args.value("-o", "--out")
        // Marks are read in order, so --color affects only the marks after it.
        var marks: [(String, String)] = []
        var remaining: [String] = []
        var i = 0
        let markFlags: Set = ["--box", "--circle", "--arrow", "--step", "--text", "--blur", "--color"]
        while i < args.rest.count {
            let a = args.rest[i]
            if markFlags.contains(a) {
                guard i + 1 < args.rest.count else { throw CLIError("\(a) needs a value") }
                marks.append((a, args.rest[i + 1]))
                i += 2
            } else {
                remaining.append(a)
                i += 1
            }
        }
        args = ArgReader(remaining)
        guard let input = args.positional() else { throw CLIError("mark needs an image: snip mark IMAGE --box x,y,w,h …") }
        try args.finish()
        guard !marks.filter({ $0.0 != "--color" }).isEmpty else { throw CLIError("no marks given (try --box, --arrow, --step, --text, --blur)") }

        let (image, scale) = try ImageFile.read(input)
        let out: URL
        if let outPath {
            out = outputURL(outPath, ext: "png", prefix: "mark")
        } else {
            let src = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
            out = src.deletingPathExtension().appendingPathExtension("marked.png")
        }
        let marked = try Markup.draw(marks, on: image, scale: scale)
        try ImageFile.writePNG(marked, scale: scale, to: out)
        report(["path": out.path, "width": marked.width, "height": marked.height, "marks": marks.count], json: json)
    }

    // MARK: ocr

    static func ocr(_ argv: [String]) async throws {
        var args = ArgReader(argv)
        let json = args.flag("--json")
        let image: CGImage
        if let path = args.positional() {
            image = try ImageFile.read(path).0
            try args.finish()
        } else {
            let target = try await Target.resolve(&args)
            try args.finish()
            image = try await target.capture()
        }
        // macOS compiles the text model for each new binary the first time; say so rather than look stuck.
        let modelCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ProcessInfo.processInfo.processName).appendingPathComponent("com.apple.e5rt.e5bundlecache")
        if !FileManager.default.fileExists(atPath: modelCache.path) {
            FileHandle.standardError.write("snip: first text recognition on this Mac; macOS is preparing its text model (can take a few minutes, once).\n".data(using: .utf8)!)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let lines: [[String: Any]] = (request.results ?? []).compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            let b = obs.boundingBox // normalized, bottom-left origin
            let box = [b.minX * w, (1 - b.maxY) * h, b.width * w, b.height * h].map { Int($0.rounded()) }
            return ["text": top.string, "box": box, "confidence": (Double(top.confidence) * 100).rounded() / 100]
        }
        if json {
            report(["width": image.width, "height": image.height, "lines": lines], json: true)
        } else {
            print(lines.compactMap { $0["text"] as? String }.joined(separator: "\n"))
        }
    }

    // MARK: windows

    static func windows(_ argv: [String]) async throws {
        var args = ArgReader(argv)
        let json = args.flag("--json")
        try args.finish()
        try Permissions.requireScreenRecording()
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let list = Windows.visible(in: content).map { w -> [String: Any] in
            ["id": Int(w.windowID), "app": w.owningApplication?.applicationName ?? "", "title": w.title ?? "",
             "frame": [w.frame.minX, w.frame.minY, w.frame.width, w.frame.height].map { Int($0.rounded()) }]
        }
        if json {
            report(["windows": list], json: true)
        } else {
            for w in list {
                let f = (w["frame"] as! [Int]).map(String.init).joined(separator: ",")
                print("\(w["id"]!)\t\(w["app"]!)\t\(w["title"]!)\t\(f)")
            }
        }
    }
}

/// Posts scroll-wheel events at one point on screen.
struct ScrollEvents {
    let point: CGPoint

    init(at point: CGPoint) { self.point = point }

    func movePointer() {
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(120_000)
    }

    /// Positive scrolls down (content moves up). Sent in small pixel steps so apps don't drop or accelerate them.
    func scroll(points: CGFloat) {
        var left = Int(points.rounded())
        while left != 0 {
            let chunk = left > 0 ? min(left, 60) : max(left, -60)
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-chunk), wheel2: 0, wheel3: 0)
            event?.location = point
            event?.post(tap: .cghidEventTap)
            left -= chunk
            usleep(8_000)
        }
    }

    func restoreMouse(to p: CGPoint) {
        CGWarpMouseCursorPosition(p)
    }
}

/// `snip mark`: Snip's annotations drawn onto an image file.
enum Markup {
    static func color(_ name: String) throws -> NSColor {
        switch name.lowercased() {
        case "red": return palette[0]
        case "yellow": return palette[1]
        case "blue": return palette[2]
        case "green": return palette[3]
        case "black": return palette[4]
        case "white": return palette[5]
        default:
            let hex = name.hasPrefix("#") ? String(name.dropFirst()) : name
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { throw CLIError("unknown color \"\(name)\"") }
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
    }

    static func draw(_ marks: [(String, String)], on image: CGImage, scale: CGFloat) throws -> CGImage {
        let w = image.width, h = image.height, H = CGFloat(h)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw CLIError("can't draw on this image") }
        let canvas = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(image, in: canvas)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        // Input is top-left pixels; the context is bottom-left.
        func rect(_ v: [CGFloat]) -> CGRect { CGRect(x: v[0], y: H - v[1] - v[3], width: v[2], height: v[3]) }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: H - y) }
        var color = palette[0]
        var step = 0
        lazy var mosaic: CGImage? = {
            let input = CIImage(cgImage: image)
            let filter = CIFilter.pixellate()
            filter.inputImage = input.clampedToExtent()
            filter.scale = Float(8 * scale)
            filter.center = .zero
            guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
            return CIContext().createCGImage(output, from: input.extent)
        }()

        for (flag, value) in marks {
            switch flag {
            case "--color":
                color = try self.color(value)
            case "--box":
                Annotation.rect(rect(try numbers(value, count: 4, what: flag)), color, 4 * scale).draw(mosaic: nil, canvas: canvas)
            case "--circle":
                Annotation.ellipse(rect(try numbers(value, count: 4, what: flag)), color, 4 * scale).draw(mosaic: nil, canvas: canvas)
            case "--arrow":
                let v = try numbers(value, count: 4, what: flag)
                Annotation.arrow(point(v[0], v[1]), point(v[2], v[3]), color, 4 * scale).draw(mosaic: nil, canvas: canvas)
            case "--step":
                let v = try numbers(value, count: 2, what: flag)
                step += 1
                Annotation.marker(step, point(v[0], v[1]), color, 13 * scale).draw(mosaic: nil, canvas: canvas)
            case "--text":
                let parts = value.split(separator: ",", maxSplits: 2).map(String.init)
                guard parts.count == 3, let x = Double(parts[0]), let y = Double(parts[1]) else {
                    throw CLIError("--text wants x,y,LABEL, got \"\(value)\"")
                }
                let size = 18 * scale
                let lineHeight = ceil(NSFont.systemFont(ofSize: size, weight: .medium).boundingRectForFont.height)
                let frame = CGRect(x: x, y: H - y - lineHeight, width: CGFloat(w) - x, height: lineHeight)
                // A soft pill keeps an agent's label readable on any screenshot.
                let textWidth = (parts[2] as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium)]).width
                let pad = 6 * scale
                let pill = CGRect(x: frame.minX + 2 - pad, y: frame.minY - pad / 2, width: textWidth + pad * 2, height: lineHeight + pad)
                NSBezierPath(roundedRect: pill, xRadius: 5 * scale, yRadius: 5 * scale).fill(color.isLight ? NSColor(white: 0.1, alpha: 0.85) : NSColor(white: 1, alpha: 0.92))
                Annotation.text(parts[2], frame, color, size).draw(mosaic: nil, canvas: canvas)
            case "--blur":
                guard let mosaic else { continue }
                ctx.saveGState()
                ctx.clip(to: rect(try numbers(value, count: 4, what: flag)))
                ctx.interpolationQuality = .none
                ctx.draw(mosaic, in: canvas)
                ctx.restoreGState()
            default:
                break
            }
        }
        guard let result = ctx.makeImage() else { throw CLIError("can't draw on this image") }
        return result
    }
}

/// Lets `snip record --background` return at once and `snip stop` find it later.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

enum Background {
    private static var signalSources: [DispatchSourceSignal] = []

    /// A flag that SIGINT or SIGTERM sets instead of killing the process.
    static func interruptFlag() -> Flag {
        let flag = Flag()
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { flag.set() }
            source.resume()
            signalSources.append(source)
        }
        return flag
    }
    static var stateFile: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("snip").appendingPathComponent("recording.json")
    }

    static func writeState(path: String) throws {
        try FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["pid": Int(getpid()), "path": path])
        try data.write(to: stateFile)
    }

    static func readState() -> (pid_t, String)? {
        guard let data = try? Data(contentsOf: stateFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = obj["pid"] as? Int, let path = obj["path"] as? String else { return nil }
        guard kill(pid_t(pid), 0) == 0 else {
            clearState()
            return nil
        }
        return (pid_t(pid), path)
    }

    static func clearState() { try? FileManager.default.removeItem(at: stateFile) }

    /// Returns on --seconds, Ctrl-C, SIGTERM or `snip stop` (SIGINT).
    static func waitForStop(seconds: Double?) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "snip.signals")
            var fired = false
            var sources: [DispatchSourceSignal] = []
            func finish() {
                guard !fired else { return }
                fired = true
                sources.forEach { $0.cancel() }
                done.resume()
            }
            for sig in [SIGINT, SIGTERM] {
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
                source.setEventHandler { finish() }
                source.resume()
                sources.append(source)
            }
            if let seconds { queue.asyncAfter(deadline: .now() + seconds) { finish() } }
        }
    }

    /// Starts `snip record …` in its own session so it outlives the shell that ran it, then reports its file.
    static func spawnRecording(_ rest: [String]) throws {
        var args = ArgReader(rest)
        let json = args.flag("--json")
        if readState() != nil { throw CLIError("a recording is already running. Stop it with `snip stop`.") }
        let out = outputURL(try args.value("-o", "--out"), ext: "mp4", prefix: "recording")
        let child = ["record", "--quiet", "-o", out.path] + args.rest
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("snip/recording.log").path
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, log, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        let argv = ([exe] + child).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, exe, &actions, &attr, argv, environ)
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attr)
        guard status == 0 else { throw CLIError("could not start the recording (error \(status))") }

        // Wait until the child is actually capturing (it writes the state file), or report why it died.
        for _ in 0..<100 {
            if let (running, _) = readState(), running == pid {
                report(["path": out.path, "pid": Int(pid), "stop": "snip stop"], json: json)
                return
            }
            var code: Int32 = 0
            if waitpid(pid, &code, WNOHANG) == pid {
                let why = (try? String(contentsOfFile: log, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw CLIError(why.flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: "snip: ", with: "") } ?? "the recording stopped right away")
            }
            usleep(100_000)
        }
        throw CLIError("the recording did not start within 10 seconds")
    }
}
