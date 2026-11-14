import XCTest
import Testing
@testable import SwiftTerm

final class TerminalSymbolFallbackTests: XCTestCase {
    func testPrivateUseBoundaries() {
        // Keep these cases mirrored in Android's TerminalSymbolFallbackTest.java.
        for cp in [0xE000, 0xF8FF, 0xF0000, 0xFFFFD, 0x100000, 0x10FFFD] {
            XCTAssertTrue(TerminalSymbolFallback.isPrivateUse(cp))
        }
        for cp in [-1, 0xDFFF, 0xF900, 0xEFFFF, 0xFFFFE, 0xFFFFF, 0x10FFFE, 0x10FFFF, 0x110000] {
            XCTAssertFalse(TerminalSymbolFallback.isPrivateUse(cp))
        }
    }

    func testOrdinarySymbolsAreExcluded() {
        for cp in [0x23FB, 0x23FC, 0x23FD, 0x23FE, 0x2630, 0x2665, 0x26A1,
                   0x276C, 0x276D, 0x276E, 0x276F, 0x2770, 0x2771, 0x2B58] {
            XCTAssertFalse(TerminalSymbolFallback.isPrivateUse(cp))
        }
    }

    func testAllowedCells() {
        XCTAssertEqual(TerminalSymbolFallback.allowedCells(columns: 1, nextCellExists: true, nextCellIsBlank: true), 2)
        XCTAssertEqual(TerminalSymbolFallback.allowedCells(columns: 1, nextCellExists: false, nextCellIsBlank: true), 1)
        XCTAssertEqual(TerminalSymbolFallback.allowedCells(columns: 1, nextCellExists: true, nextCellIsBlank: false), 1)
        XCTAssertEqual(TerminalSymbolFallback.allowedCells(columns: 2, nextCellExists: true, nextCellIsBlank: true), 3)
    }

    func testScaleAndPlacement() {
        // cp, columns, exists, blank, w,h,advance,ascent,descent,minX,minY,maxX,maxY,bleed,sx,sy,x,baseline.
        // Literal tables must match Android's TerminalSymbolFallbackTest.java.
        let cases: [[Double]] = [
            [0xE0A0, 1, 1, 0, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 0.6, 0.6, 0, 9.4],
            [0xE0A0, 1, 1, 1, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 1, 1, 0, 7],
            [0xE0A0, 1, 0, 1, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 0.6, 0.6, 0, 9.4],
            [0xF0001, 1, 1, 0, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 0.6, 0.6, 0, 9.4],
            [0xE725, 1, 1, 1, 8, 26, 20, 16, 4, 0, -4, 20, 16, 0, 0.8, 0.8, 0, 8.2],
            [0xF09B, 2, 1, 0, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 1, 1, 0, 7],
            [0xF418, 1, 1, 0, 24, 26, 20, 16, 4, 0, -4, 20, 16, 0, 1, 1, 0, 7],
            [0xE0B0, 1, 1, 1, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 0.6, 1.3, 0, 5.2],
            [0xE0D7, 1, 0, 0, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 0.6, 1.3, 0, 5.2],
            [0xE0D8, 1, 1, 0, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 0.6, 0.6, 0, 9.4],
            [0xE0AF, 1, 1, 0, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 0.6, 0.6, 0, 9.4],
            [0xE0B0, 2, 1, 1, 12, 26, 20, 16, 4, 0, -4, 20, 16, 0, 1.2, 1.3, 0, 5.2],
            [0xF09B, 1, 1, 0, 12, 10, 20, 16, 4, 0, -4, 20, 16, 0, 0.6, 0.6, 0, 1.4],
            [0xE0B0, 1, 1, 0, 1200, 2600, 2048, 1638, 410, -123, -421, 1325, 1649, 0.5, 0.829419889503, 1.25652173913, 101.518646409, 528.495652174],
            [0xE0B2, 1, 1, 0, 1200, 2600, 2048, 1638, 410, 723, -421, 2171, 1649, 0.5, 0.829419889503, 1.25652173913, -600.17058011, 528.495652174],
            [0xE0B8, 1, 1, 0, 1200, 2600, 2048, 1638, 410, -103, -420, 2047, 1648, 0.5, 0.558604651163, 1.25773694391, 57.0362790698, 527.749516441],
            [0xE0CE, 1, 1, 0, 1200, 2600, 2048, 1638, 410, 0, -358, 2047, 1586, 0.5, 0.586712261847, 1.33796296296, -0.5, 478.490740741],
            [0xEE04, 1, 1, 0, 1200, 2600, 2048, 1638, 410, -102, -278, 2150, 1506, 0.5, 0.532859680284, 0.532859680284, 54.351687389, 972.824156306],
            [0xEE04, 1, 1, 1, 1200, 2600, 2048, 1638, 410, -102, -278, 2150, 1506, 0.5, 1, 1, 102, 686],
            [0xEE04, 1, 1, 0, 12, 26, 20, 16, 4, 0, 0, 0, 0, 0.5, 0.6, 0.6, 0, 9.4],
            [0xE0B0, 1, 1, 0, 12, 26, 20, 16, 4, 0, 0, 0, 0, 0.5, 0.6, 1.3, 0, 5.2],
            [0xE0B2, 1, 1, 0, 12, 26, 20, 16, 4, 1, -4, 1, 16, 0.5, 0.6, 1.3, 0, 5.2],
            [0xEE04, 1, 1, 0, 12, 26, 20, 16, 4, -1, 0, 21, 0, 0.5, 0.6, 0.6, 0, 9.4],
        ]
        for c in cases {
            let result = TerminalSymbolFallback.layout(codePoint: Int(c[0]), columns: Int(c[1]),
                nextCellExists: c[2] != 0, nextCellIsBlank: c[3] != 0,
                cellWidth: c[4], cellHeight: c[5], advance: c[6], ascent: c[7], descent: c[8],
                inkMinX: c[9], inkMinY: c[10], inkMaxX: c[11], inkMaxY: c[12], bleed: c[13])
            XCTAssertEqual(Double(result.scaleX), c[14], accuracy: 0.00001)
            XCTAssertEqual(Double(result.scaleY), c[15], accuracy: 0.00001)
            XCTAssertEqual(Double(result.offsetX), c[16], accuracy: 0.00001)
            XCTAssertEqual(Double(result.baseline), c[17], accuracy: 0.00001)
        }
    }

    func testOnlySingleScalarCellsCanSubstitute() {
        // cp, scalarCount, ownGlyph, symbolsGlyph, expected. Mirror the Java decision table.
        let cases = [
            [0xF09B, 1, 0, 1, 1],
            [0xF09B, 2, 0, 1, 0],
            [0xF0001, 2, 0, 1, 0],
            [0xF09B, 0, 0, 1, 0],
            [0x23FB, 1, 0, 1, 0],
            [0xE0B0, 1, 1, 1, 0],
            [0xE000, 1, 0, 0, 0],
            [0xE000, 1, 1, 0, 0]
        ]
        for c in cases {
            XCTAssertEqual(TerminalSymbolFallback.shouldSubstitute(codePoint: c[0], scalarCount: c[1],
                ownFaceHasGlyph: c[2] != 0, symbolsFaceHasGlyph: c[3] != 0), c[4] != 0)
        }
    }
}

@Test func symbolContentCacheStaysBoundedAndAnswersSurviveClear() {
    var cache = SymbolCache<Int, Bool>()
    for i in 0..<(TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY * 3) {
        let key = TerminalSymbolFallback.PRIVATE_USE_BMP_START + i
        cache[key] = i % 2 == 0
        #expect(cache.count <= TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY)
        #expect(cache[key] == (i % 2 == 0))
    }
    cache[TerminalSymbolFallback.PRIVATE_USE_BMP_START] = true
    #expect(cache[TerminalSymbolFallback.PRIVATE_USE_BMP_START] == true)
    cache[TerminalSymbolFallback.PRIVATE_USE_BMP_START + 1] = false
    #expect(cache[TerminalSymbolFallback.PRIVATE_USE_BMP_START + 1] == false)
}
