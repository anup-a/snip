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
    /// The last accepted move, where the next search starts (scrolling speed changes smoothly).
    private var lastDy: Int?
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
        guard let match = Stitcher.match(lastRows, rows, height: frame.height, ignored: ignored, hint: lastDy) else {
            if Stitcher.isSameView(lastRows, rows) { return .unchanged }
            // Content moved down (scrolled back up, or bounced at the end): wait for it to come back.
            if Stitcher.match(rows, lastRows, height: frame.height, ignored: ignored, hint: nil) != nil { return .unchanged }
            return .lost
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
        lastDy = match.dy
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
    /// about the scroll. A row lines up when nearly all of those columns agree (a quarter may disagree:
    /// a video or scrollbar nobody has flagged yet). Up to a fifth of the rows that hold any content may
    /// still disagree, for a hover highlight or a blinking caret moving across the page. A wrong offset
    /// misaligns almost every row with content, so it can't pass.
    public static func match(_ a: [UInt8], _ b: [UInt8], height h: Int, ignored: [Bool], hint: Int?) -> Match? {
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

        // A row "has content" when its moving columns aren't one flat colour; blank rows match anything.
        func hasContent(_ rows: [UInt8], _ y: Int) -> Bool {
            let o = y * w
            var lo = 255, hi = 0
            for i in moving {
                let v = Int(rows[o + i])
                lo = min(lo, v)
                hi = max(hi, v)
            }
            return hi - lo > 24
        }
        let contentA = (0..<h).map { hasContent(a, $0) }
        let contentB = (0..<h).map { hasContent(b, $0) }
        let mc = moving.count
        let dropColumns = mc / 4
        var off = [Bool](repeating: false, count: band * mc)
        var columnMisses = [Int](repeating: 0, count: mc)

        /// Mismatched samples per 1024 after dropping the worst quarter of columns (a video, the
        /// scrollbar) and the worst fifth of rows with content (a hover highlight, a caret), plus the
        /// untrimmed count to break ties.
        func score(_ dy: Int) -> (trimmed: Int, raw: Int) {
            let n = band - dy
            for c in 0..<mc { columnMisses[c] = 0 }
            var total = 0
            var rows: [Int] = []
            rows.reserveCapacity(n)
            for r in 0..<n {
                let y = top + r
                guard contentA[y + dy] || contentB[y] else { continue }
                rows.append(r)
                let oa = (y + dy) * w, ob = y * w, ro = r * mc
                for c in 0..<mc {
                    let i = moving[c]
                    let miss = abs(Int(a[oa + i]) - Int(b[ob + i])) > tol
                    off[ro + c] = miss
                    if miss {
                        columnMisses[c] += 1
                        total += 1
                    }
                }
            }
            guard rows.count >= 16 else { return (.max, .max) }
            let keptRows = rows.count - rows.count / 5
            let keptColumns = mc - dropColumns
            let worstColumns = Set((0..<mc).sorted { columnMisses[$0] > columnMisses[$1] }.prefix(dropColumns))
            var rowMisses: [Int] = rows.map { r in
                let ro = r * mc
                var m = 0
                for c in 0..<mc where off[ro + c] && !worstColumns.contains(c) { m += 1 }
                return m
            }
            rowMisses.sort(by: >)
            let residual = rowMisses.dropFirst(rows.count / 5).reduce(0, +)
            return (residual * 1024 / (keptRows * keptColumns), total * 1024 / (rows.count * mc))
        }

        let maxDy = band - minOverlap
        // Rank every offset on a few dozen rows with content, then score the best few in full.
        let contentRowsB = (top..<(top + band)).filter { contentB[$0] }
        var quick: [(dy: Int, cost: Int)] = []
        quick.reserveCapacity(maxDy)
        for dy in 1...maxDy {
            let limitY = top + band - dy
            let usableRows = contentRowsB.prefix { $0 < limitY }
            guard !usableRows.isEmpty else { continue }
            let stride = max(1, usableRows.count / 40)
            var cost = 0, count = 0
            for k in Swift.stride(from: usableRows.startIndex, to: usableRows.endIndex, by: stride) {
                let y = usableRows[k]
                let oa = (y + dy) * w, ob = y * w
                var m = 0
                for i in moving where abs(Int(a[oa + i]) - Int(b[ob + i])) > tol { m += 1 }
                cost += min(m, mc / 3) // one hover row can't sink the true offset
                count += 1
            }
            quick.append((dy, cost * 1024 / count))
        }
        var candidates = Set(quick.sorted { $0.cost < $1.cost }.prefix(12).map(\.dy))
        if let hint, hint <= maxDy { candidates.insert(hint) }

        var best = (dy: 0, score: Int.max, raw: Int.max)
        for dy in candidates.sorted() {
            let s = score(dy)
            if s.trimmed <= 10, s.raw < best.raw || (s.raw == best.raw && s.trimmed < best.score) {
                best = (dy, s.trimmed, s.raw)
            }
        }
        // Under ~1% of the remaining samples may be off.
        guard best.score <= 10 else { return nil }

        // Columns that disagree on rows that otherwise line up don't scroll with the page.
        let n = band - best.dy
        var counts = [Int](repeating: 0, count: w)
        var good = 0
        for y in top..<(top + n) {
            let oa = (y + best.dy) * w, ob = y * w
            let misses = moving.filter { abs(Int(a[oa + $0]) - Int(b[ob + $0])) > tol }
            guard misses.count <= dropColumns else { continue } // a hover row, not a column
            good += 1
            for i in misses { counts[i] += 1 }
        }
        var dynamic = none
        for i in moving where counts[i] * 25 > good { dynamic[i] = true } // over 4% of matching rows
        return Match(dy: best.dy, bottom: bottom, dynamic: dynamic)
    }
}
