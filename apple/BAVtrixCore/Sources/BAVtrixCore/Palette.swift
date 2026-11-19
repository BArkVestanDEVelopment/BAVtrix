import Foundation

/// Final colour of a lit cell: depth shade, trail fade and head brightness applied.
public enum Palette {
    private static func scale(_ c: UInt8, _ k: Int) -> UInt8 {
        UInt8(min((Int(c) * k + 127) / 255, 255))
    }

    /// Returns nil for empty cells.
    public static func color(cell: Cell, row: Int, sim: RainSim) -> RGBA? {
        guard cell.flags & CellFlag.on != 0 else { return nil }
        let cfg = sim.config
        let bright = cell.flags & (CellFlag.head | CellFlag.flash) != 0
        let special = cell.flags & CellFlag.specialStream != 0
        var c: RGBA
        switch (special, bright) {
        case (false, true): c = cfg.fg
        case (false, false): c = cfg.fade
        case (true, true): c = cfg.specialFg
        case (true, false): c = cfg.specialFade
        }

        // The trail fades out towards its end; the head keeps full brightness. 32 steps keep
        // the number of distinct colours (and repaints) small.
        let slot = Int(cell.sid) < sim.slots.count ? sim.slots[Int(cell.sid)] : Slot()
        let age = Float(max(slot.head - row, 0))
        let len = Float(max(slot.len, 1))
        var fade: Float = 1
        if !bright {
            let f = 0.12 + 0.88 * powf(min(max(1 - age / len, 0), 1), 1.3)
            fade = (f * 32).rounded() / 32
        }
        let boost: Float = bright ? cfg.headBrightness : 1
        let shade = Int(min(Float(cell.shade) * fade * boost, 255))
        c.r = scale(c.r, shade)
        c.g = scale(c.g, shade)
        c.b = scale(c.b, shade)
        if boost > 1 {
            // Brighter than the configured colour: push it towards white.
            let t = min((boost - 1) * 0.5, 0.6)
            func lift(_ v: UInt8) -> UInt8 { UInt8(Float(v) + (255 - Float(v)) * t) }
            c.r = lift(c.r)
            c.g = lift(c.g)
            c.b = lift(c.b)
        }
        return c
    }
}

extension Palette {
    /// Brightness of a lit cell for the picture effect (0.06...1): far streams (low depth shade)
    /// and the fading end of a trail show the picture dimmer, so the picture gets depth too.
    public static func depthLevel(cell: Cell, row: Int, sim: RainSim) -> Float {
        let bright = cell.flags & (CellFlag.head | CellFlag.flash) != 0
        let slot = Int(cell.sid) < sim.slots.count ? sim.slots[Int(cell.sid)] : Slot()
        let age = Float(max(slot.head - row, 0))
        let len = Float(max(slot.len, 1))
        let fade: Float = bright ? 1 : 0.12 + 0.88 * powf(min(max(1 - age / len, 0), 1), 1.3)
        let level = min(Float(cell.shade) * fade / 255, 1)
        let v = 0.06 + 0.94 * powf(level, 2.2)
        return (v * 32).rounded() / 32
    }
}
