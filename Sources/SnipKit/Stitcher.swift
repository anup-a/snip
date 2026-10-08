import CoreGraphics
import Foundation

/// Joins successive frames of a scrolling region into one image.
///
/// Each new frame is matched against the last one kept: rows that stay put at the top and bottom
/// (sticky headers and footers) are left out, the moving band is slid until it lines up, and the
/// rows that scrolled into view are appended. Frames that didn't move, or moved back up, are skipped.
/// Columns that change on their own (a playing video, a sticky sidebar) are learned and left out of matching.
public final class Stitcher {
    /// Longest image Snip builds, in pixels; the capture stops there.
    public static let maxHeight = 30_000
    private static let columns = 96

    private let lock = NSLock()
    private var first: CGImage?
    private var last: CGImage?
    private var lastRows: [UInt8] = []
    private var slices: [CGImage] = []
    private var footer: Int?
    /// Sample columns that don't follow the scroll; ignored when matching.
    private var ignored = [Bool](repeating: false, count: Stitcher.columns)
    public private(set) var height = 0

    public init() {}

    public var isFull: Bool { lock.withLock { height >= Stitcher.maxHeight } }

    public enum Result { case added, unchanged, lost }

    /// `.lost` means the region changed but no longer overlaps the last kept frame (scrolled too fast).
    /// Pass `still` when you know nothing was scrolled since the last frame: whatever changed anyway
    /// (a playing video, a blinking cursor) is then left out of matching.
    public func add(_ frame: CGImage, still: Bool = false) -> Result {
        let rows = Stitcher.rowSignatures(frame)
        lock.lock()
        defer { lock.unlock() }
        guard let previous = last else {
            first = frame
            last = frame
            lastRows = rows
            height = frame.height
            return .added
        }
        guard frame.width == previous.width, frame.height == previous.height else { return .unchanged }
        if still {
            let changed = Stitcher.changedColumns(lastRows, rows, height: frame.height)
            if changed.count * 2 <= Stitcher.columns {
                for i in changed { ignored[i] = true }
                return .unchanged
            }
        }
        guard let match = Stitcher.match(lastRows, rows, height: frame.height, ignored: ignored) else {
            return Stitcher.isSameView(lastRows, rows) ? .unchanged : .lost
        }
        for (i, dynamic) in match.dynamic.enumerated() where dynamic { ignored[i] = true }
        guard match.dy > 0 else { return .unchanged }
        // The sticky footer is fixed from the first move so every slice is cut at the same line.
        let foot = footer ?? match.bottom
        footer = foot
        let cut = CGRect(x: 0, y: frame.height - foot - match.dy, width: frame.width, height: match.dy)
        guard cut.minY >= 0, let slice = frame.cropping(to: cut) else { return .lost }
        slices.append(slice)
        last = frame
        lastRows = rows
        height += match.dy
        return .added
    }

    /// True when two frames show the same view, allowing a small animated patch (a video, a spinner).
    public static func isSameView(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var off = 0
        for i in 0..<a.count where abs(Int(a[i]) - Int(b[i])) > tolerance { off += 1 }
        return Double(off) / Double(a.count) <= 0.06
    }

    /// The stitched image; `width` scales it down for previews.
    public func compose(width: Int? = nil) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let first, let last else { return nil }
        let foot = footer ?? 0
        let k = width.map { min(1, CGFloat($0) / CGFloat(first.width)) } ?? 1
        let outW = Int((CGFloat(first.width) * k).rounded())
        let outH = Int((CGFloat(height) * k).rounded())
        guard outW > 0, outH > 0,
              let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = k < 1 ? .medium : .none
        // Pieces top to bottom: the first frame above the footer, each scrolled-in slice, then the last frame's footer.
        var pieces: [CGImage] = []
        if let top = first.cropping(to: CGRect(x: 0, y: 0, width: first.width, height: first.height - foot)) { pieces.append(top) }
        pieces += slices
        if foot > 0, let bottom = last.cropping(to: CGRect(x: 0, y: last.height - foot, width: last.width, height: foot)) {
            pieces.append(bottom)
        }
        var top = 0
        for piece in pieces {
            let y = CGFloat(height - top - piece.height) * k
            ctx.draw(piece, in: CGRect(x: 0, y: y, width: CGFloat(piece.width) * k, height: CGFloat(piece.height) * k))
            top += piece.height
        }
        return ctx.makeImage()
    }

    /// Each row squeezed to a few grey samples: cheap to compare, still distinct for text and UI.
    public static func rowSignatures(_ image: CGImage) -> [UInt8] {
        let w = columns, h = image.height
        var data = [UInt8](repeating: 0, count: w * h)
        data.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data // row 0 is the top of the image
    }

    /// A sample "differs" when it is more than this many grey levels off.
    private static let tolerance = 12

    public struct Match {
        /// How far content moved up, in pixels; 0 means it didn't scroll.
        public let dy: Int
        /// Height of the static band at the bottom (a sticky footer).
        public let bottom: Int
        /// Columns that didn't follow the scroll at this offset.
        public let dynamic: [Bool]
    }

    /// Columns with content that changed between two frames at the same position.
    static func changedColumns(_ a: [UInt8], _ b: [UInt8], height h: Int) -> [Int] {
        let w = columns
        var count = [Int](repeating: 0, count: w)
        for y in 0..<h {
            let o = y * w
            for i in 0..<w where abs(Int(a[o + i]) - Int(b[o + i])) > tolerance { count[i] += 1 }
        }
        return (0..<w).filter { count[$0] * 100 > h } // more than 1% of rows
    }

    /// Finds how far content moved up between two frames.
    ///
    /// Only columns whose content changed are compared: blank margins and sticky sidebars say nothing
    /// about the scroll. A match must be near exact, though the worst quarter of those columns may
    /// disagree (an animation nobody has flagged yet); blank columns never count, so this can't
    /// paper over a wrong offset.
    public static func match(_ a: [UInt8], _ b: [UInt8], height h: Int, ignored: [Bool]) -> Match? {
        let w = columns, tol = tolerance
        let none = [Bool](repeating: false, count: w)
        let usable = (0..<w).filter { !ignored[$0] }
        guard usable.count >= w / 4 else { return nil }
        let moving = changedColumns(a, b, height: h).filter { !ignored[$0] }
        if moving.isEmpty { return Match(dy: 0, bottom: 0, dynamic: none) }

        func still(_ y: Int) -> Bool {
            let o = y * w
            for i in usable where abs(Int(a[o + i]) - Int(b[o + i])) > tol { return false }
            return true
        }
        var top = 0
        while top < h, still(top) { top += 1 }
        var bottom = 0
        while bottom < h - top, still(h - 1 - bottom) { bottom += 1 }
        top = min(top, h * 2 / 5)
        bottom = min(bottom, h * 2 / 5)
        let band = h - top - bottom
        let minOverlap = max(24, band / 6)
        guard band > minOverlap + 1 else { return nil }

        let outliers = moving.count / 4
        let samplesPerRow = moving.count - outliers
        var counts = [Int](repeating: 0, count: w)
        /// Mismatched samples per 1024 over the overlap, after dropping the worst `outliers` columns.
        func score(_ dy: Int, limit: Int) -> Int {
            let n = band - dy
            for i in moving { counts[i] = 0 }
            let cap = limit == .max ? Int.max : limit * n * samplesPerRow / 1024 + outliers * n
            var total = 0
            for y in top..<(top + n) {
                let oa = (y + dy) * w, ob = y * w
                for i in moving where abs(Int(a[oa + i]) - Int(b[ob + i])) > tol {
                    counts[i] += 1
                    total += 1
                }
                if total > cap { return .max }
            }
            let worst = moving.map { counts[$0] }.sorted(by: >).prefix(outliers).reduce(0, +)
            return (total - worst) * 1024 / (n * samplesPerRow)
        }
        var best = (dy: 0, score: Int.max)
        for dy in 1...(band - minOverlap) {
            let s = score(dy, limit: best.score)
            if s < best.score { best = (dy, s) }
            if best.score == 0 { break }
        }
        // Under ~1% of the compared samples may be off.
        guard best.score <= 10 else { return nil }

        _ = score(best.dy, limit: .max)
        let n = band - best.dy
        var dynamic = none
        for i in moving where counts[i] * 25 > n { dynamic[i] = true } // over 4% of rows: not scrolling with the page
        return Match(dy: best.dy, bottom: bottom, dynamic: dynamic)
    }
}
