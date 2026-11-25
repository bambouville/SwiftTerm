#if os(macOS) || os(iOS) || os(visionOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreText
import XCTest
@testable import SwiftTerm

final class SupplementarySymbolRenderingTests: XCTestCase {
    func testSupplementaryIconKeepsSymbolSubstitutionAcrossRedraws() async throws {
        try await MainActor.run {
            guard let path = ProcessInfo.processInfo.environment["SWIFTTERM_TEST_SYMBOL_FONT"] else {
                throw XCTSkip("Set SWIFTTERM_TEST_SYMBOL_FONT to Symbols Nerd Font Mono")
            }
            let provider = try XCTUnwrap(CGDataProvider(url: URL(fileURLWithPath: path) as CFURL))
            let font = try XCTUnwrap(CGFont(provider))
            let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 100),
                                    font: TTFont.monospacedSystemFont(ofSize: 20, weight: .regular))
            view.symbolsFont = CTFontCreateWithGraphicsFont(font, 20, nil, nil) as TTFont
            view.resize(cols: 4, rows: 1)
            view.feed(text: "\u{F024B} X")

            let buffer = view.terminal.displayBuffer
            let row = buffer.yBase
            let line = buffer.lines[row]
            XCTAssertEqual(view.terminal.getCharacter(for: line[0]), "\u{F024B}")
            XCTAssertEqual(view.terminal.getCharacter(col: 0, row: 0), "\u{F024B}")
            XCTAssertEqual(line[0].width, 1)
            let first = view.prepareCoreGraphicsRow(row: row, line: line, cols: buffer.cols)
            let redraw = view.prepareCoreGraphicsRow(row: row, line: line, cols: buffer.cols)
            let metal = view.buildAttributedString(row: row, line: line, cols: buffer.cols, forMetal: true)

            for info in [first.info, redraw.info, metal] {
                let symbol = try XCTUnwrap(info.symbol(atSourceColumn: 0))
                XCTAssertEqual(symbol.font.fontName, "SymbolsNFM")
                XCTAssertEqual(symbol.cell.column, 0)
                XCTAssertNil(info.symbol(atSourceColumn: 2))
            }

#if os(iOS) || os(visionOS)
            let shapedLine = try XCTUnwrap(first.segments.first?.ctLine)
            XCTAssertTrue(shapedLine === redraw.segments.first?.ctLine, "Reuse the prepared CoreGraphics row")
#endif
        }
    }

#if os(iOS) || os(visionOS)
    func testRawCharacterCodeBecomingAssignedInvalidatesCachedRow() async {
        await MainActor.run {
            let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 100), font: nil)
            view.resize(cols: 4, rows: 1)
            let terminal = view.terminal!
            let buffer = terminal.displayBuffer
            let row = buffer.yBase
            let line = buffer.lines[row]
            let attribute = line[0].attribute
            let assignedCode = terminal.makeCharData(attribute: attribute, char: "\u{F024B}").code
            line[0] = terminal.makeCharData(attribute: attribute, code: assignedCode + 1)
            let unresolved = view.prepareCoreGraphicsRow(row: row, line: line, cols: buffer.cols)
            XCTAssertEqual(unresolved.segments.first?.segment.attributedString.string.first, " ")

            let icon: Character = "\u{F0001}"
            XCTAssertEqual(terminal.makeCharData(attribute: attribute, char: icon).code, line[0].code)
            let resolved = view.prepareCoreGraphicsRow(row: row, line: line, cols: buffer.cols)
            XCTAssertEqual(resolved.segments.first?.segment.attributedString.string.first, icon)
        }
    }
#endif
}
#endif
