import XCTest
@testable import BAVtrixCore

final class SimTests: XCTestCase {
    private func run(_ sim: RainSim, seconds: Float, frameMs: Float = 33) {
        var t: Float = 0
        while t < seconds * 1000 {
            sim.advance(dtMs: frameMs)
            t += frameMs
        }
    }

    private func litCells(_ sim: RainSim) -> Int {
        sim.cells.filter { $0.flags & CellFlag.on != 0 }.count
    }

    func testRainAppearsAndFillsPartOfTheScreen() {
        let sim = RainSim(cols: 40, rows: 80, config: RainConfig(), seed: 1)
        run(sim, seconds: 20)
        XCTAssertGreaterThan(sim.streamCount, 0)
        XCTAssertGreaterThan(litCells(sim), 0)
        XCTAssertLessThan(litCells(sim), sim.cells.count)
    }

    func testEveryLitCellBelongsToAKnownSlot() {
        let sim = RainSim(cols: 30, rows: 60, config: RainConfig(), seed: 2)
        run(sim, seconds: 15)
        for c in sim.cells where c.flags & CellFlag.on != 0 {
            XCTAssertLessThan(Int(c.sid), sim.slots.count)
            XCTAssertLessThan(Int(c.glyph), max(GlyphData.shapes.count, sim.config.specialChars.count))
        }
    }

    func testDensitySettingChangesCoverage() {
        var sparse = RainConfig()
        sparse.spawnRate = 0.1
        var dense = RainConfig()
        dense.spawnRate = 0.9
        let a = RainSim(cols: 50, rows: 80, config: sparse, seed: 3)
        let b = RainSim(cols: 50, rows: 80, config: dense, seed: 3)
        run(a, seconds: 40)
        run(b, seconds: 40)
        XCTAssertGreaterThan(litCells(b), litCells(a))
    }

    func testSameSeedGivesSameRain() {
        let a = RainSim(cols: 20, rows: 40, config: RainConfig(), seed: 7)
        let b = RainSim(cols: 20, rows: 40, config: RainConfig(), seed: 7)
        run(a, seconds: 10)
        run(b, seconds: 10)
        XCTAssertEqual(a.cells.map { $0.glyph }, b.cells.map { $0.glyph })
        XCTAssertEqual(a.cells.map { $0.flags }, b.cells.map { $0.flags })
    }

    func testStreamsEventuallyLeaveTheScreen() {
        var cfg = RainConfig()
        cfg.maxStream = 5
        let sim = RainSim(cols: 10, rows: 20, config: cfg, seed: 4)
        run(sim, seconds: 5)
        XCTAssertLessThanOrEqual(sim.streamCount, 5)
        // After a long time slots are recycled instead of growing without bound.
        run(sim, seconds: 120)
        XCTAssertLessThan(sim.slots.count, 100)
    }

    func testPaletteFadesTheTrailAndKeepsTheHeadBright() {
        let sim = RainSim(cols: 20, rows: 60, config: RainConfig(), seed: 5)
        run(sim, seconds: 20)
        var headBrightness = 0, trailBrightness = 0, heads = 0, trails = 0
        for row in 0..<sim.rows {
            for col in 0..<sim.cols {
                let cell = sim.cells[row * sim.cols + col]
                guard let c = Palette.color(cell: cell, row: row, sim: sim) else { continue }
                let lum = Int(c.r) + Int(c.g) + Int(c.b)
                if cell.flags & CellFlag.head != 0 { headBrightness += lum; heads += 1 }
                else if cell.flags & CellFlag.flash == 0 { trailBrightness += lum; trails += 1 }
            }
        }
        XCTAssertGreaterThan(heads, 0)
        XCTAssertGreaterThan(trails, 0)
        XCTAssertGreaterThan(headBrightness / heads, trailBrightness / trails)
    }

    func testConfigRoundTripsThroughJSON() throws {
        var cfg = RainConfig()
        cfg.spawnRate = 0.77
        cfg.specialStrings = ["BAVtrix", "hello world"]
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(RainConfig.self, from: data)
        XCTAssertEqual(cfg, back)
        XCTAssertEqual(back.specialChars.count, Set("BAVtrixhello world").count)
    }
}
