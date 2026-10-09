import AppKit
import SnipKit

let version = "0.2.0"

let usage = """
snip \(version): screenshots, scrolling screenshots, recordings and markup for macOS, made for agents.

Usage:
  snip shot    [target] [-o out.png]                 screenshot a window, app, region or screen
  snip scroll  [target] [-o out.png] [--at x,y] [--max px]
                                                     scroll a window top to bottom, stitch one long image
  snip record  [target] [-o out.mp4] [--seconds n] [--background] [--no-cursor]
                                                     record video until --seconds, Ctrl-C or `snip stop`
  snip stop                                          stop the background recording, print its file
  snip mark    IMAGE [-o out.png] [marks…]           draw on an image in Snip's style
  snip ocr     IMAGE | [target]                      print the text (with --json: text + pixel boxes)
  snip windows                                       list windows you can target
  snip pin     IMAGE [--seconds n]                   float an image on the user's screen

Targets (default: the main screen):
  --app NAME          the app's frontmost window ("Safari", "Slack"; case-insensitive, partial match)
  --window ID         a window id from `snip windows`
  --region x,y,w,h    screen points, top-left origin
  --screen N          a whole display (1 = main)

Marks, applied in order (pixel coordinates of IMAGE, top-left origin):
  --box x,y,w,h       rectangle          --circle x,y,w,h   ellipse
  --arrow x1,y1,x2,y2 arrow to x2,y2     --step x,y         numbered marker (1, 2, 3…)
  --text x,y,LABEL    text               --blur x,y,w,h     pixelate (hide private info)
  --color NAME|#hex   red (default), yellow, blue, green, black, white; applies to later marks
  --scale N           stroke and text size multiplier (default: 2 for Retina-size images, else 1)

Output: prints the file path. Add --json for {"path", "width", "height", …}.
Files go to $TMPDIR/snip/ unless -o is given.

Permissions: shot/scroll/record/ocr need Screen Recording for the app running snip (your terminal).
scroll also needs Accessibility, because it sends scroll events.
"""

/// SNIP_TRACE=1 prints how long each step took, measured from process launch, to stderr.
enum Trace {
    static let enabled = ProcessInfo.processInfo.environment["SNIP_TRACE"] != nil
    private static let launch: Double = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let t = info.kp_proc.p_un.__p_starttime
        return Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000
    }()

    static func mark(_ step: String) {
        guard enabled else { return }
        let ms = (Date().timeIntervalSince1970 - launch) * 1000
        FileHandle.standardError.write(String(format: "%7.1f ms  %@\n", ms, step).data(using: .utf8)!)
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

/// Pops flags and values off the command line.
struct ArgReader {
    private(set) var rest: [String]
    init(_ args: [String]) { rest = args }

    mutating func flag(_ names: String...) -> Bool {
        guard let i = rest.firstIndex(where: names.contains) else { return false }
        rest.remove(at: i)
        return true
    }

    mutating func value(_ names: String...) throws -> String? {
        guard let i = rest.firstIndex(where: names.contains) else { return nil }
        guard i + 1 < rest.count else { throw CLIError("\(rest[i]) needs a value") }
        let v = rest[i + 1]
        rest.removeSubrange(i...(i + 1))
        return v
    }

    /// The first argument that isn't a flag. An existing file wins, so a flag's value (`--region 0,0,9,9`) isn't mistaken for it.
    mutating func positional() -> String? {
        let candidates = rest.indices.filter { !rest[$0].hasPrefix("-") }
        let isFile = { (i: Int) in FileManager.default.fileExists(atPath: (rest[i] as NSString).expandingTildeInPath) }
        guard let i = candidates.first(where: isFile) ?? candidates.first.flatMap({ i in
            // Not a file: only take it when it isn't right after a flag (that's the flag's value).
            i == 0 || !rest[i - 1].hasPrefix("-") ? i : nil
        }) else { return nil }
        return rest.remove(at: i)
    }

    func finish() throws {
        if let extra = rest.first { throw CLIError("unexpected argument: \(extra)") }
    }
}

func numbers(_ s: String, count: Int, what: String) throws -> [CGFloat] {
    let parts = s.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == count, parts.allSatisfy({ $0 != nil }) else {
        throw CLIError("\(what) wants \(count) comma-separated numbers, got \"\(s)\"")
    }
    return parts.map { CGFloat($0!) }
}

/// Writes the result line: the path, or JSON with --json.
func report(_ fields: [String: Any], json: Bool) {
    if json {
        let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        print(String(data: data, encoding: .utf8)!)
    } else if let path = fields["path"] as? String {
        print(path)
    } else if let text = fields["text"] as? String {
        print(text)
    }
}

func defaultOutput(_ ext: String, prefix: String) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("snip")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return dir.appendingPathComponent("\(prefix)-\(f.string(from: Date())).\(ext)")
}

func outputURL(_ path: String?, ext: String, prefix: String) -> URL {
    guard let path else { return defaultOutput(ext, prefix: prefix) }
    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
}

// MARK: Entry

Trace.mark("main")
var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "help" : arguments.removeFirst()

switch command {
case "help", "-h", "--help":
    print(usage)
    exit(0)
case "version", "--version", "-v":
    print(version)
    exit(0)
case "pin":
    // Pin runs AppKit's own event loop, so it stays off the async path.
    do { try Pin.run(arguments) } catch { fail(error) }
default:
    // Only the commands that drive other apps need AppKit's app object; setting it up costs more than a screenshot.
    if ["scroll", "record"].contains(command) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Trace.mark("NSApplication")
    }
    Task {
        do {
            switch command {
            case "shot": try await Commands.shot(arguments)
            case "scroll": try await Commands.scroll(arguments)
            case "record": try await Commands.record(arguments)
            case "stop": try await Commands.stop(arguments)
            case "mark": try Commands.mark(arguments)
            case "ocr": try await Commands.ocr(arguments)
            case "windows": try await Commands.windows(arguments)
            default: throw CLIError("unknown command \"\(command)\". Run `snip help`.")
            }
            exit(0)
        } catch {
            fail(error)
        }
    }
    dispatchMain()
}

func fail(_ error: Error) -> Never {
    let message = (error as? CLIError)?.description ?? (error as? LocalizedError)?.errorDescription ?? "\(error)"
    FileHandle.standardError.write("snip: \(message)\n".data(using: .utf8)!)
    exit(1)
}
