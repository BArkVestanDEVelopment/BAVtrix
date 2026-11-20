import XCTest
@testable import BAVtrixCore

final class GlyphDataTests: XCTestCase {
    func testEveryGlyphHasStrokesInsideTheGrid() {
        XCTAssertGreaterThanOrEqual(GlyphData.shapes.count, 60)
        for shape in GlyphData.shapes {
            XCTAssertFalse(shape.strokes.isEmpty, "\(shape.id) has no strokes")
            for stroke in shape.strokes {
                XCTAssertTrue(stroke.count >= 4 && stroke.count % 2 == 0, "\(shape.id): bad stroke length")
                for i in stride(from: 0, to: stroke.count, by: 2) {
                    XCTAssertTrue((0..<GlyphData.cols).contains(stroke[i]), "\(shape.id): x out of grid")
                    XCTAssertTrue((0..<GlyphData.rows).contains(stroke[i + 1]), "\(shape.id): y out of grid")
                }
            }
        }
    }

    func testIdsAreUnique() {
        let ids = GlyphData.shapes.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAtlasDrawsEveryGlyph() {
        let atlas = GlyphAtlas(glyphSize: 12, scale: 2)
        XCTAssertEqual(atlas.count, GlyphData.shapes.count)
        XCTAssertEqual(atlas.cellWidth, GlyphAtlas.cellSize(glyphSize: 12).width)
    }
}