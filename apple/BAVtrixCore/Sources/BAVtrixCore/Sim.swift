import Foundation

public enum CellFlag {
    public static let on: UInt8 = 1
    public static let head: UInt8 = 2
    public static let specialStream: UInt8 = 4
    public static let specialGlyph: UInt8 = 8
    /// Short flash of a trail character (drawn with the head colour for one frame).
    public static let flash: UInt8 = 16
}

public struct Cell {
    public var glyph: UInt16 = 0
    public var flags: UInt8 = 0
    /// Per-stream brightness (depth effect), 0...255.
    public var shade: UInt8 = 0
    /// Slot of the stream that drew this cell (index into `RainSim.slots`).
    public var sid: UInt16 = 0

    public init() {}
}

/// Head position and trail length of a stream, looked up by the renderer through `Cell.sid`.
public struct Slot {
    public var head = 0
    public var len = 0
}

private struct Stream {
    var col: Int
    var slot: UInt16
    var head: Int
    var len: Int
    var speed: Float
    var shade: UInt8
    var acc: Float = 0
    var special: (index: Int, start: Int)?
    /// True while this stream is the one running down its column.
    var ownsColumn = true
}

public final class RainSim {
    public let cols: Int
    public let rows: Int
    public private(set) var cells: [Cell]
    public private(set) var slots: [Slot] = []

    private var freeSlots: [UInt16] = []
    private var streams: [Stream] = []
    private var occupied: [Bool]
    private var rng: Rng
    public var config: RainConfig {
        didSet { rebuildDerived() }
    }
    private var charsetCount = 1
    private var specialIndexStrings: [[UInt16]] = []

    public init(cols: Int, rows: Int, config: RainConfig, seed: UInt64) {
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
        self.config = config
        self.cells = Array(repeating: Cell(), count: max(cols, 1) * max(rows, 1))
        self.occupied = Array(repeating: false, count: max(cols, 1))
        self.rng = Rng(seed: seed)
        rebuildDerived()
    }

    private func rebuildDerived() {
        charsetCount = max(GlyphData.shapes.count, 1)
        specialIndexStrings = config.specialIndexStrings
    }

    /// Number of active streams (for tests and statistics).
    public var streamCount: Int { streams.count }

    private func clearOwn(col: Int, row: Int, sid: UInt16) {
        guard row >= 0, row < rows else { return }
        let idx = row * cols + col
        if cells[idx].flags != 0 && cells[idx].sid == sid {
            cells[idx] = Cell()
        }
    }

    private func spawn(dtMs: Float) {
        let p = config
        let d = min(max(p.spawnRate, 0.01), 0.97)
        // Trail length range. Denser rain also gets longer streams by default.
        let autoMax = max(Int(Float(rows) * (0.3 + 0.5 * d)), 12)
        let tmax = max(p.trailMax > 0 ? p.trailMax : autoMax, 3)
        let tmin = min(max(p.trailMin, 2), tmax)
        let avgSpeed = (1 + p.speedVariance) / 2
        // A column is busy while the head of its stream is on screen; after that the next
        // stream may start while the old trail is still fading out below.
        let headMs = max(Float(rows) * p.refreshMs / avgSpeed, 1)
        let rate = d / ((1 - d) * headMs)
        let chance = 1 - exp(-rate * dtMs)

        for col in 0..<cols {
            if streams.count >= p.maxStream { break }
            if occupied[col] || rng.unit() > chance { continue }

            var slot: UInt16
            if let s = freeSlots.popLast() {
                slot = s
            } else {
                if slots.count >= Int(UInt16.max) { break }
                slots.append(Slot())
                slot = UInt16(slots.count - 1)
            }
            occupied[col] = true

            var special: (index: Int, start: Int)?
            if !specialIndexStrings.isEmpty && rng.unit() < p.specialProbability {
                let idx = rng.below(specialIndexStrings.count)
                let len = specialIndexStrings[idx].count
                let room = max(rows - len, 1)
                special = (idx, rng.below(room))
            }

            let sv = p.speedVariance
            let speed = 1 + rng.unit() * (sv - 1)
            // Depth: faster streams look closer (brighter), with some random variation.
            let near: Float = sv > 1 ? (speed - 1) / (sv - 1) : 0.5
            let depth = 0.55 * near + 0.45 * rng.unit()
            let len: Int
            if p.monotonousCleanup {
                len = max(p.backTrace, 2)
            } else {
                len = tmin + rng.below(tmax - tmin + 1)
            }
            let head = -1 - rng.below(8)
            slots[Int(slot)] = Slot(head: head, len: len)
            streams.append(Stream(
                col: col, slot: slot, head: head, len: len, speed: speed,
                shade: UInt8(min(45 + 210 * depth, 255)), special: special))
        }
    }

    /// Moves one stream down by a row; returns false when it has left the screen.
    private func step(_ si: Int) -> Bool {
        let col = streams[si].col
        let len = streams[si].len
        let shade = streams[si].shade
        let special = streams[si].special
        let sid = streams[si].slot
        let head = streams[si].head + 1
        streams[si].head = head
        slots[Int(sid)].head = head

        if head - 1 >= 0 && head - 1 < rows {
            let idx = (head - 1) * cols + col
            if cells[idx].sid == sid { cells[idx].flags &= ~CellFlag.head }
        }
        if head >= 0 && head < rows {
            var flags = CellFlag.on | CellFlag.head | (special != nil ? CellFlag.specialStream : 0)
            var glyph = UInt16(rng.below(charsetCount))
            if let sp = special {
                let s = specialIndexStrings[sp.index]
                let off = head - sp.start
                if off >= 0 && off < s.count {
                    glyph = s[off]
                    flags |= CellFlag.specialGlyph
                }
            }
            var cell = Cell()
            cell.glyph = glyph
            cell.flags = flags
            cell.shade = shade
            cell.sid = sid
            cells[head * cols + col] = cell
        }
        if head >= rows && streams[si].ownsColumn {
            // The head has left the screen: the column may start a new stream.
            streams[si].ownsColumn = false
            occupied[col] = false
        }
        // The end of the trail is erased as the head moves on.
        clearOwn(col: col, row: head - len, sid: sid)
        if config.randomizedCleanup {
            let hi = head - config.leading
            let lo = hi - config.spacePad
            let r = lo + rng.below(max(hi - lo + 1, 1))
            clearOwn(col: col, row: r, sid: sid)
        }
        return head - len < rows
    }

    private func mutate(col: Int, row: Int, sid: UInt16, flash: Bool) {
        guard row >= 0, row < rows else { return }
        let g = UInt16(rng.below(charsetCount))
        let idx = row * cols + col
        var cell = cells[idx]
        if cell.flags & CellFlag.on != 0 && cell.sid == sid && cell.flags & CellFlag.specialGlyph == 0 {
            cell.glyph = g
            if flash { cell.flags |= CellFlag.flash }
            cells[idx] = cell
        }
    }

    /// Random character changes inside the streams: this is what makes the rain shimmer.
    private func flicker(dtMs: Float) {
        for i in 0..<cells.count { cells[i].flags &= ~CellFlag.flash }
        let s = config.flicker
        let hs = config.headFlicker
        if s <= 0 && hs <= 0 { return }
        let k = min(max(dtMs / 33, 0.3), 3)
        // 8 attempts per frame: at strength 0.5 about 4 characters of each trail change.
        let pMut = min(s * k, 1)
        for si in 0..<streams.count {
            let col = streams[si].col
            let head = streams[si].head
            let len = streams[si].len
            let sid = streams[si].slot
            // Head shimmer: `hs` is the chance per 33 ms, so a 120 Hz screen does not strobe.
            if rng.unit() < min(hs * dtMs / 33, 1) { mutate(col: col, row: head, sid: sid, flash: false) }
            for n in 0..<8 {
                if rng.unit() > pMut { continue }
                let row = head - 1 - rng.below(max(len, 1))
                let flash = n < 2 && rng.unit() < s * 0.5
                mutate(col: col, row: row, sid: sid, flash: flash)
            }
        }
    }

    /// Advances the simulation by `dtMs` milliseconds.
    public func advance(dtMs: Float) {
        spawn(dtMs: dtMs)
        flicker(dtMs: dtMs)
        var i = 0
        while i < streams.count {
            streams[i].acc += dtMs * streams[i].speed
            let n = min(Int(streams[i].acc / config.refreshMs), 64)
            streams[i].acc = n == 64 ? 0 : streams[i].acc - Float(n) * config.refreshMs
            var alive = true
            for _ in 0..<n where !step(i) {
                alive = false
                break
            }
            if alive {
                i += 1
            } else {
                let st = streams.swapRemove(i)
                if st.ownsColumn { occupied[st.col] = false }
                freeSlots.append(st.slot)
            }
        }
    }
}

extension Array {
    /// Removes the element at `i` by swapping in the last one (order is not preserved).
    fileprivate mutating func swapRemove(_ i: Int) -> Element {
        let last = removeLast()
        if i < count {
            let removed = self[i]
            self[i] = last
            return removed
        }
        return last
    }
}
