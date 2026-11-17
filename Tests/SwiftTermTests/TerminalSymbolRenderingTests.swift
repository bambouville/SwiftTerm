#if os(macOS)
import AppKit
import CoreText
import XCTest
@testable import SwiftTerm

final class TerminalSymbolRenderingTests: XCTestCase {
    private func symbolsFont() throws -> NSFont {
        guard let path = ProcessInfo.processInfo.environment["SWIFTTERM_TEST_SYMBOL_FONT"] else {
            throw XCTSkip("Set SWIFTTERM_TEST_SYMBOL_FONT to the unmodified Symbols Nerd Font Mono release")
        }
        return try font(url: URL(fileURLWithPath: path), size: 37)
    }

    private func font(url: URL, size: CGFloat) throws -> NSFont {
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let graphicsFont = try XCTUnwrap(CGFont(provider))
        return CTFontCreateWithGraphicsFont(graphicsFont, size, nil, nil) as NSFont
    }

    private func view(text: String) throws -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 100),
                                font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular))
        view.symbolsFont = try symbolsFont()
        view.frame.size = CGSize(width: view.cellDimension.width * 4, height: view.cellDimension.height)
        view.resize(cols: 4, rows: 1)
        view.nativeForegroundColor = .white
        view.nativeBackgroundColor = .black
        view.feed(text: text)
        return view
    }

    private func info(_ view: TerminalView, forMetal: Bool = false) -> ViewLineInfo {
        let buffer = view.terminal.displayBuffer
        return view.buildAttributedString(row: buffer.yBase, line: buffer.lines[buffer.yBase], cols: buffer.cols, forMetal: forMetal)
    }

    private func symbol(_ info: ViewLineInfo) throws -> NSAttributedString {
        for segment in info.segments {
            if let index = segment.symbols.keys.sorted().first {
                return segment.attributedString.attributedSubstring(from: NSRange(location: index,
                    length: (segment.attributedString.string as NSString).rangeOfComposedCharacterSequence(at: index).length))
            }
        }
        return try XCTUnwrap(nil as NSAttributedString?)
    }

    func testExplicitChoiceOverridesPrivateUseFallbacksButLeavesOrdinaryTextAlone() throws {
        let view = try view(text: "\u{F09B}\u{F0001}\u{E30D}X")
        let row = info(view)
        XCTAssertEqual(row.segments.flatMap { $0.symbols.keys }.sorted(), [0, 1, 3])
        for index in row.segments[0].symbols.keys {
            let font = try XCTUnwrap(row.segments[0].attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(font.fontName, "SymbolsNFM")
        }
        view.symbolsFont = nil
        XCTAssertFalse(info(view).segments.contains { $0.attributedString.attribute(SwiftTermSymbolOffsetKey,
            at: 0, effectiveRange: nil) != nil })
        view.symbolsFont = try symbolsFont()
        for cp in [0x23FB, 0x23FC, 0x23FD, 0x23FE, 0x2630, 0x2665, 0x26A1,
                   0x276C, 0x276D, 0x276E, 0x276F, 0x2770, 0x2771, 0x2B58] {
            view.feed(text: "\u{1B}[H" + String(UnicodeScalar(cp)!))
            XCTAssertNil(info(view).segments[0].attributedString.attribute(SwiftTermSymbolOffsetKey,
                at: 0, effectiveRange: nil))
        }
    }

    func testSelectedFaceKeepsItsOwnPowerlineGlyphsInEveryStyle() throws {
        guard let path = ProcessInfo.processInfo.environment["SWIFTTERM_TEST_SYMBOL_FONT"] else {
            throw XCTSkip("Set SWIFTTERM_TEST_SYMBOL_FONT")
        }
        let url = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("jetbrains_mono.ttf")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("JetBrains Mono fixture is absent") }
        let view = try view(text: "")
        view.font = try font(url: url, size: 20)
        for style in ["0", "1", "3", "1;3"] {
            view.feed(text: "\u{1B}[H\u{1B}[\(style)m\u{E0B0}\u{E0A0}")
            XCTAssertFalse(info(view).segments.contains { $0.attributedString.attribute(SwiftTermSymbolOffsetKey,
                at: 0, effectiveRange: nil) != nil })
        }
    }

    func testNeighborRefitsWithoutSplittingTheParagraph() throws {
        let view = try view(text: "\u{F09B} X")
        let first = try symbol(info(view))
        let large = try XCTUnwrap(first.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        view.feed(text: "\u{1B}[1;2HX")
        let row = info(view)
        let fitted = try symbol(row)
        let small = try XCTUnwrap(fitted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertLessThan(CTFontGetMatrix(small).a, CTFontGetMatrix(large).a)
        XCTAssertEqual(row.segments[0].column, 0)
        XCTAssertEqual(row.segments[0].characterCount, 2)
        XCTAssertEqual(row.segments.count, 1)
        XCTAssertEqual(CTFontGetSize(small), CTFontGetSize(view.font))
        view.feed(text: "\u{1B}[1;2H \u{0301}")
        let marked = try symbol(info(view))
        let markedFont = try XCTUnwrap(marked.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(CTFontGetMatrix(markedFont).a, CTFontGetMatrix(small).a)
        view.feed(text: "\u{1B}[1;2H\u{1B}[41m \u{1B}[0m")
        let coloredBlank = try symbol(info(view))
        let grown = try XCTUnwrap(coloredBlank.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(CTFontGetMatrix(grown).a, CTFontGetMatrix(large).a)
        // Both the atlas and backing-scale font cache use this key.
        let smallIdentity = try XCTUnwrap(fitted.attribute(SwiftTermSymbolIdentityKey, at: 0, effectiveRange: nil) as? SymbolFontIdentity)
        let largeIdentity = try XCTUnwrap(first.attribute(SwiftTermSymbolIdentityKey, at: 0, effectiveRange: nil) as? SymbolFontIdentity)
        let key = MetalFontCache.glyphKey(font: small, glyph: 1)
        XCTAssertEqual(key, MetalFontCache.glyphKey(font: large, glyph: 1))
        XCTAssertNotEqual(SymbolGlyphKey(ordinary: key, identity: smallIdentity),
                          SymbolGlyphKey(ordinary: key, identity: largeIdentity))
        let generation = view.symbolFontGeneration
        view.terminal.clearUpdateRange()
        XCTAssertNil(view.terminal.getUpdateRange())
        view.symbolsFont = nil
        XCTAssertGreaterThan(view.symbolFontGeneration, generation)
        XCTAssertNotNil(view.terminal.getUpdateRange(), "An idle terminal must redraw when the fallback changes")
    }

    func testCustomRenderedNeighborsDoNotAllowSymbolBorrowing() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["SWIFTTERM_TEST_SYMBOL_FONT"])
        let primary = try font(url: URL(fileURLWithPath: path).deletingLastPathComponent()
            .appendingPathComponent("ubuntu_mono.ttf"), size: 16)
        for neighbor in ["\u{2502}", "\u{2588}", "\u{10EEEE}"] {
            func fixture(_ icon: String) throws -> TerminalView {
                let view = try self.view(text: "")
                view.font = primary
                view.frame.size = CGSize(width: view.cellDimension.width * 4, height: view.cellDimension.height)
                view.resize(cols: 4, rows: 1)
                XCTAssertTrue(view.customBlockGlyphs)
                view.feed(text: "\u{1B}[31m" + icon + "\u{1B}[32m" + neighbor)
                return view
            }
            let view = try fixture("\u{F09B}")
            for metal in [false, true] {
                let style = try XCTUnwrap(info(view, forMetal: metal).symbol(atSourceColumn: 0))
                XCTAssertEqual(CTFontGetMatrix(style.font).a, view.cellDimension.width / 16,
                    accuracy: 0.0001, "An occupied custom cell cannot be borrowed")
            }
            let reference = try fixture(" ")
            let actual = try renderedRow(view).pixels
            let expected = try renderedRow(reference, expectsInk: neighbor != "\u{10EEEE}").pixels
            let scale = view.backingScaleFactor()
            let width = Int(ceil(view.bounds.width * scale)) + 8
            let left = Int(view.cellDimension.width * scale) + 4
            let right = Int(view.cellDimension.width * 2 * scale) + 4
            for y in 4..<Int(view.cellDimension.height * scale) + 4 {
                for x in left..<right {
                    let i = (y * width + x) * 4
                    XCTAssertEqual(Array(actual[i..<i+4]), Array(expected[i..<i+4]), "Custom cell changed at \(x),\(y)")
                }
            }
        }
    }

    func testFollowingOrdinaryInkWinsAboveBorrowedSymbol() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["SWIFTTERM_TEST_SYMBOL_FONT"])
        let base = try font(url: URL(fileURLWithPath: path).deletingLastPathComponent()
            .appendingPathComponent("ubuntu_mono.ttf"), size: 64)
        // AppKit does not synthesize a missing family italic. Supply the same
        // oblique transform as Android so this test actually overlaps the cells.
        var oblique = CGAffineTransform(a: 1, b: 0, c: 0.35, d: 1, tx: 0, ty: 0)
        let primary = CTFontCreateCopyWithAttributes(base, 64, &oblique, nil) as NSFont
        func frame(_ text: String) throws -> [UInt8] {
            let view = try self.view(text: "")
            view.font = primary
            view.frame.size = CGSize(width: view.cellDimension.width * 4, height: view.cellDimension.height)
            view.resize(cols: 4, rows: 1)
            view.feed(text: text)
            return try renderedRow(view).pixels
        }
        let blue = "\u{1B}[38;2;0;0;255m\u{F0C8} "
        let yellow = "\u{1B}[38;2;255;255;0;3m_"
        let full = try frame(blue + yellow)
        let icon = try frame(blue)
        let foreground = try frame("  " + yellow)
        var overlap = 0
        for i in stride(from: 0, to: full.count, by: 4) where icon[i + 2] > 0 && foreground[i] > 0 {
            overlap += 1
            XCTAssertEqual(full[i], foreground[i], "Following ink must remain above the blue symbol")
        }
        XCTAssertGreaterThan(overlap, 0, "The fixture must overlap the borrowed symbol")
    }

    func testImageCoveredBlankDoesNotAllowSymbolBorrowing() throws {
        let view = try view(text: "\u{F09B} ")
        let buffer = view.terminal.displayBuffer
        let image = NSImage(size: view.cellDimension)
        let stripe = TerminalView.AppleImage(image: image, width: Int(view.cellDimension.width),
            height: Int(view.cellDimension.height), onCol: 1)
        buffer.attachImage(stripe, toLineAt: buffer.yBase)
        for metal in [false, true] {
            let style = try XCTUnwrap(info(view, forMetal: metal).symbol(atSourceColumn: 0))
            XCTAssertEqual(CTFontGetMatrix(style.font).a, view.cellDimension.width / 20, accuracy: 0.0001)
        }
    }

    func testRightToLeftBorrowingAlsoRespectsPhysicalCustomCells() throws {
        let view = try view(text: "")
        view.font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        view.frame.size = CGSize(width: view.cellDimension.width * 5, height: view.cellDimension.height)
        view.resize(cols: 5, rows: 1)
        view.feed(text: "א\u{2588}\u{F09B} x")
        let row = info(view)
        let style = try XCTUnwrap(row.symbol(atSourceColumn: 2))
        XCTAssertEqual(style.cell.column, 0)
        XCTAssertEqual(row.blockElements.first?.column, 1)
        XCTAssertEqual(CTFontGetMatrix(style.font).a, view.cellDimension.width / 20, accuracy: 0.0001)
    }

    func testCurvedSeparatorFitUsesTightOutlineExtrema() throws {
        let symbols = try symbolsFont()
        let primary = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        for cp in [0xE0C0, 0xE0C2] {
            let cache = TerminalSymbolFontCache()
            let fit = try XCTUnwrap(cache.resolve(codePoint: UInt32(cp), scalarCount: 1,
                selected: primary, symbols: symbols, pointSize: 2048, columns: 1,
                nextCellExists: false, nextCellIsBlank: false, cellSize: CGSize(width: 60, height: 100),
                baseline: 20, deviceScale: 1))
            var character = UniChar(cp), glyph = CGGlyph()
            CTFontGetGlyphsForCharacters(fit.font, &character, &glyph, 1)
            let outline = try XCTUnwrap(CTFontCreatePathForGlyph(fit.font, glyph, nil)).boundingBoxOfPath
            XCTAssertEqual(outline.maxY + fit.offset + 20, 100.5, accuracy: 0.02)
            XCTAssertEqual(outline.minY + fit.offset + 20, -0.5, accuracy: 0.02)
            XCTAssertEqual(outline.minX + fit.offsetX, -0.5, accuracy: 0.02)
            XCTAssertEqual(outline.maxX + fit.offsetX, 60.5, accuracy: 0.02)
        }
    }

    func testCurvedSeparatorsFillTallRows() throws {
        for cp in [0xE0C0, 0xE0C2] {
            let view = try view(text: "")
            view.font = NSFont.monospacedSystemFont(ofSize: 100, weight: .regular)
            view.frame.size = CGSize(width: view.cellDimension.width * 4, height: view.cellDimension.height)
            view.resize(cols: 4, rows: 1)
            view.feed(text: String(UnicodeScalar(cp)!))
            let ink = try renderedRow(view).ink
            XCTAssertEqual(ink.minY, 0)
            XCTAssertEqual(ink.maxY, view.cellDimension.height)
        }
    }

    func testSeparatorInkReachesAllEdgesAndStaysInsideItsCells() throws {
        for cp in [0xE0B0, 0xE0B2, 0xE0B8, 0xE0CE] {
            let view = try view(text: String(UnicodeScalar(cp)!))
            let bounds = try renderedRow(view).ink
            let w = view.cellDimension.width, h = view.cellDimension.height
            XCTAssertLessThanOrEqual(bounds.minX, 0, "U+\(String(cp, radix: 16)) left")
            XCTAssertGreaterThanOrEqual(bounds.maxX, w, "U+\(String(cp, radix: 16)) right")
            XCTAssertLessThanOrEqual(bounds.minY, 0, "U+\(String(cp, radix: 16)) bottom")
            XCTAssertGreaterThanOrEqual(bounds.maxY, h, "U+\(String(cp, radix: 16)) top")
            XCTAssertGreaterThanOrEqual(bounds.minX, 0)
            XCTAssertLessThanOrEqual(bounds.maxX, w)
            XCTAssertGreaterThanOrEqual(bounds.minY, 0)
            XCTAssertLessThanOrEqual(bounds.maxY, h)
        }
    }

    func testSeparatorsLeaveAllFourNeighborBackgroundsUntouched() throws {
        for cp in [0xE0B0, 0xE0B2, 0xE0B8, 0xE0CE] {
            let view = try view(text: "")
            view.frame.size = CGSize(width: view.cellDimension.width * 3, height: view.cellDimension.height * 3)
            view.resize(cols: 3, rows: 3)
            view.feed(text: "\u{1B}[44m\u{1B}[2J\u{1B}[2;2H\u{1B}[40;37m ")
            let before = try renderedRow(view).pixels
            view.feed(text: "\u{1B}[2;2H" + String(UnicodeScalar(cp)!))
            let after = try renderedRow(view).pixels
            let scale = view.backingScaleFactor()
            let width = Int(ceil(view.bounds.width * scale)) + 8
            let cell = CGRect(x: view.cellDimension.width * scale + 4,
                y: view.cellDimension.height * scale + 4,
                width: view.cellDimension.width * scale, height: view.cellDimension.height * scale)
            for i in stride(from: 0, to: before.count, by: 4) {
                let x = CGFloat((i / 4) % width), y = CGFloat((i / 4) / width)
                if CGRect(x: x, y: y, width: 1, height: 1).intersects(cell) { continue }
                XCTAssertEqual(Array(before[i..<i+4]), Array(after[i..<i+4]), "U+\(String(cp, radix: 16)) outside (\(x),\(y))")
            }
        }
    }

    func testAdjacentSeparatorsKeepIndependentCellClips() throws {
        for cp in [0xE0B0, 0xE0B2] {
            let glyph = String(UnicodeScalar(cp)!)
            func frame(_ text: String) throws -> (TerminalView, [UInt8]) {
                let view = try self.view(text: "\u{1B}[44m\u{1B}[2J\u{1B}[H\u{1B}[40;37m  \u{1B}[H" + text)
                return (view, try renderedRow(view).pixels)
            }
            let (view, together) = try frame(glyph + glyph)
            let (_, first) = try frame(glyph + " ")
            let (_, second) = try frame(" " + glyph)
            let scale = view.backingScaleFactor()
            let width = Int(ceil(view.bounds.width * scale)) + 8
            let cellWidth = view.cellDimension.width * scale
            let cellHeight = view.cellDimension.height * scale
            for y in 4..<Int(cellHeight) + 4 {
                for x in 4..<Int(cellWidth * 2) + 4 {
                    let reference = CGFloat(x - 4) < cellWidth ? first : second
                    let i = (y * width + x) * 4
                    XCTAssertEqual(Array(together[i..<i+4]), Array(reference[i..<i+4]),
                        "U+\(String(cp, radix: 16)) crossed a cell boundary at \(x),\(y)")
                }
            }
            let row = info(view)
            let lines = view.prepareCoreGraphicsRow(row: view.terminal.displayBuffer.yBase,
                line: view.terminal.displayBuffer.lines[view.terminal.displayBuffer.yBase], cols: 4)
            XCTAssertEqual(lines.segments.flatMap { $0.symbols?.compactMap { $0 } ?? [] }.count, 2)
            XCTAssertEqual(row.segments.flatMap { $0.symbols.values }.map { $0.cell.column }.sorted(), [0, 1])
        }
    }

    func testMetalSymbolUsesItsCellAfterASeparateCombiningGlyph() throws {
        let view = try view(text: "x\u{0301}\u{F09B}z")
        let row = MetalTerminalRenderer.RowShaper().build(info(view).segments,
            normalFont: view.font, cellWidth: view.cellDimension.width)
        var actualColumn: Int?
        for segment in row {
            var processed = 0
            for run in segment.runs {
                if run.symbol != nil {
                    actualColumn = run.startColumn(segment: segment.segment, processedGlyphs: processed)
                }
                processed += run.shaperRun.glyphCount
            }
        }
        XCTAssertEqual(actualColumn, 1, "The accent is not another terminal cell")
    }

    func testRightToLeftSymbolsBorrowOnlyAVisuallyFollowingBlank() throws {
        let view = try view(text: "")
        view.font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        view.frame.size = CGSize(width: view.cellDimension.width * 6, height: view.cellDimension.height)
        view.resize(cols: 6, rows: 1)
        // Logical order: alef bet gimel icon SPACE dalet. The space is
        // visually LEFT of the icon; gimel is visually on its right.
        view.feed(text: "אבג\u{F09B} ד")
        let row = info(view)
        let style = try XCTUnwrap(row.segments.flatMap { $0.symbols.values }.first)
        XCTAssertEqual(style.cell.column, 2)
        let fitted = try symbol(row)
        let font = try XCTUnwrap(fitted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(CTFontGetMatrix(font).a, view.cellDimension.width / 20, accuracy: 0.0001)
        let shaped = MetalTerminalRenderer.RowShaper().build(row.segments,
            normalFont: view.font, cellWidth: view.cellDimension.width)
        for segment in shaped {
            var processed = 0
            for run in segment.runs {
                if run.symbol != nil {
                    XCTAssertEqual(run.startColumn(segment: segment.segment, processedGlyphs: processed), 2)
                }
                processed += run.shaperRun.glyphCount
            }
        }
    }

    func testStyledRightToLeftSymbolsKeepEachRenderersOriginalShapingScope() throws {
        let view = try view(text: "")
        view.font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        view.frame.size = CGSize(width: view.cellDimension.width * 6, height: view.cellDimension.height)
        view.resize(cols: 6, rows: 1)
        view.feed(text: "\u{1B}[31mאבג\u{1B}[32m\u{F09B} ד")
        for metal in [false, true] {
            let row = info(view, forMetal: metal)
            let style = try XCTUnwrap(row.segments.flatMap { $0.symbols.values }.first)
            XCTAssertEqual(style.cell.column, metal ? 3 : 2)
            let fitted = try symbol(row)
            let font = try XCTUnwrap(fitted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(CTFontGetMatrix(font).a, metal ? 1 : view.cellDimension.width / 20, accuracy: 0.0001)
        }
    }

    func testOrdinaryMetalFontWorkingSetDoesNotEvictAtSymbolBudget() throws {
        let cache = MetalFontCache()
        let font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        let first = cache.scaledFontFor(font: font, scale: 1, identity: nil)
        for i in 1...TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY + 1 {
            _ = cache.scaledFontFor(font: font, scale: 1 + CGFloat(i) / 1000, identity: nil)
        }
        XCTAssertEqual(cache.ordinaryScaledFontCount, TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY + 2)
        XCTAssertTrue(first === cache.scaledFontFor(font: font, scale: 1, identity: nil))
    }

    func testOverhangingIconInkStaysInsideItsAllowedCells() throws {
        for blank in [false, true] {
            // A black X occupies the next cell without adding visible ink.
            let view = try view(text: "\u{EE04}" + (blank ? " " : "\u{1B}[30mX"))
            let bounds = try renderedRow(view).ink
            let allowed = view.cellDimension.width * (blank ? 2 : 1)
            XCTAssertGreaterThan(bounds.width, 0)
            XCTAssertGreaterThanOrEqual(bounds.minX, 0)
            XCTAssertLessThanOrEqual(bounds.maxX, allowed)
            if blank { XCTAssertGreaterThan(bounds.width, view.cellDimension.width) }

            // Metal rasterizes the same fitted CTFont at backing scale.
            let run = try symbol(info(view))
            let font = try XCTUnwrap(run.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            let line = CTLineCreateWithAttributedString(run)
            let glyphRun = try XCTUnwrap((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
            var glyph = CGGlyph()
            CTRunGetGlyphs(glyphRun, CFRange(location: 0, length: 1), &glyph)
            let scaled = CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * view.backingScaleFactor(), nil, nil)
            let bitmap = try XCTUnwrap(CoreTextGlyphRasterizer().rasterize(font: scaled, glyph: glyph, fittedSymbol: true))
            XCTAssertLessThanOrEqual(CGFloat(bitmap.width), allowed * view.backingScaleFactor() + 2)
        }
    }

    func testMultiScalarCellsKeepTheUnsubstitutedAttributesAndPixels() throws {
        for suffix in ["\u{0301}", "\u{200D}"] {
            let view = try view(text: "\u{F09B}" + suffix + "X")
            let enabled = info(view).segments.map(\.attributedString)
            let enabledPixels = try renderedRow(view).pixels
            view.symbolsFont = nil
            let disabled = info(view).segments.map(\.attributedString)
            XCTAssertEqual(enabled.count, disabled.count)
            for (a, b) in zip(enabled, disabled) { XCTAssertTrue(a.isEqual(to: b)) }
            XCTAssertEqual(enabledPixels, try renderedRow(view).pixels)
        }
        let plain = try view(text: "\u{F09B}")
        XCTAssertNotNil(try symbol(info(plain)).attribute(SwiftTermSymbolIdentityKey, at: 0, effectiveRange: nil))
    }

    func testSymbolsDoNotMoveSurroundingRightToLeftCells() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["SWIFTTERM_TEST_SYMBOL_FONT"])
        let url = URL(fileURLWithPath: path)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        let view = try view(text: "")
        view.symbolsFont = nil
        view.font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        view.frame.size = CGSize(width: view.cellDimension.width * 5, height: view.cellDimension.height)
        view.resize(cols: 5, rows: 1)
        // LastResort's 22-point tofu spills out of a 13-point cell. Hide only
        // this foreground in both images so the comparison measures ordinary
        // text, rather than the intentionally replaced tofu's neighboring ink.
        view.feed(text: "אב\u{1B}[30m\u{F09B}\u{1B}[37mגד")
        let before = try renderedRow(view).pixels
        XCTAssertTrue(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
        defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
        view.symbolsFont = try XCTUnwrap(NSFont(name: "SymbolsNFM", size: 37))
        let after = try renderedRow(view).pixels
        let scale = view.backingScaleFactor()
        let width = Int(ceil(view.bounds.width * scale)) + 8
        let left = Int(ceil(view.cellDimension.width * 2 * scale)) + 4
        let right = Int(floor(view.cellDimension.width * 3 * scale)) + 4
        var changed = 0
        for i in stride(from: 0, to: before.count, by: 4) {
            let x = (i / 4) % width
            if x >= left && x < right { continue }
            if before[i..<i+4] != after[i..<i+4] { changed += 1 }
        }
        XCTAssertEqual(changed, 0, "Substitution must preserve every ordinary RTL cell")
    }

    func testMetalKeepsTheOriginalRightToLeftGlyphOrder() throws {
        let view = try view(text: "")
        view.font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        view.frame.size = CGSize(width: view.cellDimension.width * 5, height: view.cellDimension.height)
        view.resize(cols: 5, rows: 1)
        view.feed(text: "אב\u{F09B}גד")
        let shaper = MetalTerminalRenderer.RowShaper()
        func ordinaryGlyphs(_ row: [MetalTerminalRenderer.ShapedSegment]) -> [CGGlyph] {
            row.flatMap { $0.runs }.flatMap { run in
                run.shaperRun.glyphRuns.filter { CTFontCopyPostScriptName($0.font) as String == "CourierNewPSMT" }.flatMap(\.glyphs)
            }
        }
        let shaped = shaper.build(info(view, forMetal: true).segments, normalFont: view.font, cellWidth: view.cellDimension.width)
        let enabled = ordinaryGlyphs(shaped)
        let positions = metalOrdinaryGlyphs(shaped, cellWidth: view.cellDimension.width).map { $0.position.x }.sorted()
        let expected = [0, 1, 3, 4].map { CGFloat($0) * view.cellDimension.width }
        XCTAssertEqual(positions.count, expected.count)
        for (actual, cellX) in zip(positions, expected) {
            XCTAssertEqual(actual, cellX, accuracy: 1 / view.backingScaleFactor(),
                "RTL runs must anchor their leftmost glyph to the run's first visual cell")
        }
        view.symbolsFont = nil
        let disabled = ordinaryGlyphs(shaper.build(info(view).segments, normalFont: view.font, cellWidth: view.cellDimension.width))
        XCTAssertEqual(enabled.count, 4)
        XCTAssertEqual(enabled, disabled)
    }

    func testMetalAnchorsTextAfterMissingSymbolsToItsCellsLikeCoreGraphics() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["SWIFTTERM_TEST_SYMBOL_FONT"])
        let primary = try font(url: URL(fileURLWithPath: path).deletingLastPathComponent()
            .appendingPathComponent("ubuntu_mono.ttf"), size: 13)
        var character: UniChar = 0xEE04, missingGlyph = CGGlyph()
        XCTAssertFalse(CTFontGetGlyphsForCharacters(primary, &character, &missingGlyph, 1))
        character = 88
        var xGlyph = CGGlyph()
        XCTAssertTrue(CTFontGetGlyphsForCharacters(primary, &character, &xGlyph, 1))
        for text in ["A\u{EE04}X", "A\u{EE04}XY\u{EE04} X|", "|\u{EE04}X\u{EE04} X|"] {
            let view = try view(text: "")
            view.font = primary
            let columns = text.count + 1
            let width = view.cellDimension.width
            let tolerance = 1 / view.backingScaleFactor()
            view.frame.size = CGSize(width: width * CGFloat(columns), height: view.cellDimension.height)
            view.resize(cols: columns, rows: 1)
            view.feed(text: text)
            let row = info(view, forMetal: true)
            XCTAssertEqual(row.segments.count, 1, "Exercise text within the same styled segment")
            XCTAssertEqual(row.segments.flatMap { $0.symbols.values }.count, text.filter { $0 == "\u{EE04}" }.count)
            let originalSymbol = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{EE04}", attributes: [.font: primary]))
            XCTAssertGreaterThan(abs(CGFloat(CTLineGetTypographicBounds(originalSymbol, nil, nil, nil)) - width), tolerance,
                "The native fallback must advance differently from a terminal cell")
            let shaped = MetalTerminalRenderer.RowShaper().build(row.segments, normalFont: primary, cellWidth: width)
            let metalXs = metalOrdinaryGlyphs(shaped, cellWidth: width).filter {
                $0.glyph == xGlyph && CTFontCopyPostScriptName($0.font) as String == CTFontCopyPostScriptName(primary) as String
            }.map { $0.position.x }
            let expected = text.enumerated().compactMap { $0.element == "X" ? CGFloat($0.offset) * width : nil }
            XCTAssertEqual(metalXs.count, expected.count)

            let buffer = view.terminal.displayBuffer
            let prepared = view.prepareCoreGraphicsRow(row: buffer.yBase, line: buffer.lines[buffer.yBase], cols: columns)
            var graphicsXs: [CGFloat] = []
            for segment in prepared.segments {
                var processed = 0
                for run in segment.runs {
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    CTRunGetGlyphs(run, CFRange(), &glyphs)
                    let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
                    let runFont = try XCTUnwrap(attributes[.font] as? NSFont)
                    if CTFontCopyPostScriptName(runFont) as String == CTFontCopyPostScriptName(primary) as String {
                        for i in glyphs.indices where glyphs[i] == xGlyph {
                            // CoreGraphics places ordinary glyphs directly on this grid.
                            graphicsXs.append(CGFloat(segment.segment.column + (processed + i) * segment.segment.columnWidth) * width)
                        }
                    }
                    processed += count
                }
            }
            XCTAssertEqual(graphicsXs.count, expected.count)
            for (actual, cellX) in zip(metalXs, expected) { XCTAssertEqual(actual, cellX, accuracy: tolerance, text) }
            for (metalX, graphicsX) in zip(metalXs, graphicsXs) { XCTAssertEqual(metalX, graphicsX, accuracy: tolerance, text) }
        }
    }

    func testMetalKeepsOrdinaryMarkOffsetsAndKeysRowsByCellWidth() throws {
        let view = try view(text: "x\u{0301}\u{F09B}z")
        view.frame.size = CGSize(width: view.cellDimension.width * 3, height: view.cellDimension.height)
        view.resize(cols: 3, rows: 1)
        let shaper = MetalTerminalRenderer.RowShaper()
        let enabledInfo = info(view, forMetal: true)
        let width = view.cellDimension.width
        let enabled = metalOrdinaryGlyphs(shaper.build(enabledInfo.segments, normalFont: view.font, cellWidth: width), cellWidth: width)
        view.symbolsFont = nil
        let disabled = metalOrdinaryGlyphs(shaper.build(info(view, forMetal: true).segments, normalFont: view.font, cellWidth: width), cellWidth: width)
        XCTAssertFalse(enabled.isEmpty)
        XCTAssertEqual(enabled.count, disabled.count)
        for (actual, original) in zip(enabled, disabled) {
            XCTAssertEqual(actual.glyph, original.glyph)
            XCTAssertEqual(CTFontCopyPostScriptName(actual.font) as String, CTFontCopyPostScriptName(original.font) as String)
            XCTAssertEqual(actual.position.y, original.position.y)
        }
        XCTAssertEqual(Array(enabled.dropLast().map(\.position)), Array(disabled.dropLast().map(\.position)),
            "The base and combining mark keep their native offsets")
        XCTAssertEqual(try XCTUnwrap(enabled.last).position.x, 2 * width, accuracy: 0.001)
        let wider = metalOrdinaryGlyphs(shaper.build(enabledInfo.segments, normalFont: view.font, cellWidth: width + 3), cellWidth: width + 3)
        XCTAssertEqual(Array(wider.dropLast().map(\.position)), Array(enabled.dropLast().map(\.position)))
        XCTAssertEqual(try XCTUnwrap(wider.last).position.x, 2 * (width + 3), accuracy: 0.001,
            "A cached symbol row must anchor ordinary text using the new grid width")
    }

    func testMetalKeepsLigatureAdvancesBetweenSymbols() throws {
        let view = try view(text: "")
        view.font = try XCTUnwrap(NSFont(name: "Times-Roman", size: 20))
        let width = view.cellDimension.width
        view.frame.size = CGSize(width: width * 7, height: view.cellDimension.height)
        view.resize(cols: 7, rows: 1)
        view.feed(text: "A\u{EE04}ffi\u{EE04}X")
        let source = try XCTUnwrap(info(view, forMetal: true).segments.first)
        let text = NSMutableAttributedString(attributedString: source.attributedString)
        text.addAttribute(.ligature, value: 1, range: NSRange(location: 0, length: text.length))
        let segment = ViewLineSegment(column: source.column, columnWidth: source.columnWidth,
            characterCount: source.characterCount, attributedString: text, symbols: source.symbols)
        let originalLine = CTLineCreateWithAttributedString(segment.originalAttributedString())
        let native = try XCTUnwrap((CTLineGetGlyphRuns(originalLine) as? [CTRun])?.first {
            CTRunGetStringRange($0).location == 2
        })
        let count = CTRunGetGlyphCount(native)
        XCTAssertLessThan(count, 3, "The fixture must actually form a ligature in ffi")
        var positions = [CGPoint](repeating: .zero, count: count)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        CTRunGetPositions(native, CFRange(), &positions)
        CTRunGetGlyphs(native, CFRange(), &glyphs)
        let shaped = MetalTerminalRenderer.RowShaper().build([segment], normalFont: view.font, cellWidth: width)
        let ordinary = metalOrdinaryGlyphs(shaped, cellWidth: width)
        XCTAssertEqual(ordinary.count, count + 2)
        let firstX = try XCTUnwrap(positions.first).x
        for (actual, pair) in zip(ordinary.dropFirst().prefix(count), zip(glyphs, positions)) {
            XCTAssertEqual(actual.glyph, pair.0)
            XCTAssertEqual(actual.position.x, 2 * width + pair.1.x - firstX, accuracy: 0.001)
            XCTAssertEqual(actual.position.y, pair.1.y)
        }
        XCTAssertEqual(try XCTUnwrap(ordinary.last).position.x, 6 * width, accuracy: 0.001,
            "A ligature consumes source cells even when it produces fewer glyphs")
    }

    func testMetalSymbolMetadataHasOneBoundAcrossAllFitsAndRows() throws {
        let view = try view(text: "")
        let shaper = MetalTerminalRenderer.RowShaper()
        let fonts = MetalFontCache()
        for cp in 0xF0001..<(0xF0001 + TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY + 1) {
            view.feed(text: "\u{1B}[H" + String(UnicodeScalar(cp)!))
            let segments = info(view).segments
            let row = shaper.build(segments, normalFont: view.font, cellWidth: view.cellDimension.width)
            for segment in row { for run in segment.runs { for glyphRun in run.shaperRun.glyphRuns {
                _ = fonts.scaledFontFor(font: glyphRun.font, scale: 2, identity: run.symbolIdentity)
            } } }
            XCTAssertLessThanOrEqual(shaper.symbolCacheCount, TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY)
            XCTAssertLessThanOrEqual(fonts.symbolScaledFontCount, TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY)
        }
        view.feed(text: "\u{1B}[H\u{F0001}")
        let row = shaper.build(info(view).segments, normalFont: view.font, cellWidth: view.cellDimension.width)
        XCTAssertTrue(row.flatMap(\.runs).contains { $0.symbolIdentity != nil })
    }

    func testCoverageAndDerivedCachesAreBoundedAndFaceIsCopiedOnce() throws {
        let cache = TerminalSymbolFontCache()
        let selected = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        let symbols = try symbolsFont()
        func resolve(_ cp: Int) -> Bool {
            cache.resolve(codePoint: UInt32(cp), scalarCount: 1, selected: selected, symbols: symbols,
                pointSize: 20, columns: 1, nextCellExists: false, nextCellIsBlank: false,
                cellSize: CGSize(width: 12, height: 26), baseline: 5, deviceScale: 1) != nil
        }
        for cp in 0xE000..<(0xE000 + TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY * 3) {
            _ = resolve(cp)
            XCTAssertTrue(cache.entryCounts.allSatisfy { $0 <= TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY })
        }
        XCTAssertTrue(resolve(0xF09B))
        XCTAssertFalse(resolve(0xF8FF))
        XCTAssertEqual(cache.selectedCharacterSetCopyCount, 1)
    }

    func testBlockCursorReusesTheRowsVisualSymbolFit() throws {
        let view = try view(text: "")
        view.font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        view.frame.size = CGSize(width: view.cellDimension.width * 5, height: view.cellDimension.height)
        view.resize(cols: 5, rows: 1)
        view.feed(text: "אב\u{F09B} ד\u{1B}[1;3H")
        let buffer = view.terminal.displayBuffer
        let source = buffer.lines[buffer.yBase][2]
        let rowStyle = try XCTUnwrap(info(view).symbol(atSourceColumn: 2))
        let caret = CaretView(frame: CGRect(origin: .zero, size: view.cellDimension),
                              cursorStyle: .steadyBlock, terminal: view)
        caret.setText(ch: source)
        let cursorStyle = try XCTUnwrap(caret.symbolStyle)
        XCTAssertEqual(CTFontGetMatrix(cursorStyle.font), CTFontGetMatrix(rowStyle.font))
        XCTAssertEqual(cursorStyle.offsetX, rowStyle.offsetX)
        XCTAssertEqual(cursorStyle.offsetY, rowStyle.offsetY)
        XCTAssertLessThan(CTFontGetMatrix(cursorStyle.font).a, 1)
        let builds = view.symbolFontCache.cursorRowBuildCount
        caret.setText(ch: source)
        XCTAssertEqual(view.symbolFontCache.cursorRowBuildCount, builds, "An unchanged cursor row must reuse its fit")
        view.feed(text: "\u{1B}[1;4HX\u{1B}[1;3H")
        caret.setText(ch: source)
        XCTAssertGreaterThan(view.symbolFontCache.cursorRowBuildCount, builds)
        view.feed(text: "\u{1B}[1;4H \u{1B}[1;3H")
        let metalStyle = try XCTUnwrap(info(view, forMetal: true).symbol(atSourceColumn: 2))
        let row = RowDrawData(backgroundCells: [], glyphCellsGray: [], glyphCellsColor: [], decorationCells: [],
            underImageDraws: [], placeholderImageDraws: [], overImageDraws: [], otherImageDraws: [],
            symbols: [2: metalStyle])
        let cachedStyle = try XCTUnwrap(MetalTerminalRenderer.cursorSymbolStyle(column: 2, row: row))
        let attributes = cachedStyle.applying(to: [.foregroundColor: NSColor.red, .backgroundColor: NSColor.green])
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        XCTAssertEqual(CTFontGetMatrix(font), CTFontGetMatrix(metalStyle.font))
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, NSColor.red)
        XCTAssertEqual(attributes[.backgroundColor] as? NSColor, NSColor.green)
    }

    func testMetalSymbolsPreserveOrdinaryFallbackDecorationMetrics() throws {
        let view = try view(text: "")
        view.font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 20))
        view.feed(text: "\u{1B}[4;9mא\u{F09B}")
        let shaper = MetalTerminalRenderer.RowShaper()
        func metrics(_ row: [MetalTerminalRenderer.ShapedSegment]) throws -> [CGFloat] {
            let run = try XCTUnwrap(row.flatMap(\.runs).first { run in
                run.symbol == nil && run.shaperRun.glyphRuns.contains {
                    CTFontCopyPostScriptName($0.font) as String == "CourierNewPSMT"
                }
            })
            let selected = try XCTUnwrap(run.attributes[.font] as? NSFont)
            XCTAssertEqual(selected.fontName, "Menlo-Regular")
            let strike = run.strikethroughMetrics(scale: 2, normalFont: view.font)
            let y = try XCTUnwrap(run.shaperRun.positions.first).y
            return [y + strike.position, strike.thickness,
                    y + view.fontSet.underlinePosition(), view.fontSet.underlineThickness()]
        }
        let enabled = try metrics(shaper.build(info(view, forMetal: true).segments,
            normalFont: view.font, cellWidth: view.cellDimension.width))
        view.symbolsFont = nil
        let disabled = try metrics(shaper.build(info(view, forMetal: true).segments,
            normalFont: view.font, cellWidth: view.cellDimension.width))
        XCTAssertEqual(enabled, disabled)
    }

    func testOrdinaryCoreGraphicsPreparationHasNoSymbolArray() throws {
        let view = try view(text: "ABC")
        let buffer = view.terminal.displayBuffer
        let row = view.prepareCoreGraphicsRow(row: buffer.yBase, line: buffer.lines[buffer.yBase], cols: buffer.cols)
        XCTAssertFalse(row.segments.isEmpty)
        for segment in row.segments {
            XCTAssertFalse(segment.runs.isEmpty)
            XCTAssertNil(segment.symbols)
        }
        view.feed(text: "\u{1B}[H\u{F09B}")
        let changed = view.prepareCoreGraphicsRow(row: buffer.yBase, line: buffer.lines[buffer.yBase], cols: buffer.cols)
        XCTAssertTrue(changed.segments.contains { $0.symbols != nil })
    }

    func testRebuildingAsciiRowsNeverReadsFontMatrices() throws {
        let shaper = MetalTerminalRenderer.RowShaper()
        let cache = MetalFontCache()
        for enabled in [true, false] {
            let view = try view(text: "ABC")
            if !enabled { view.symbolsFont = nil }
            for _ in 0..<2 {
                SymbolFontIdentity.resetMatrixReadCount()
                SymbolRunStyle.resetOffsetLookupCount()
                let row = shaper.build(info(view).segments, normalFont: view.font)
                var glyphCount = 0
                for segment in row { for run in segment.runs { for glyphRun in run.shaperRun.glyphRuns {
                    let font = cache.scaledFontFor(font: glyphRun.font, scale: 2, identity: run.symbolIdentity)
                    for glyph in glyphRun.glyphs {
                        _ = MetalFontCache.glyphKey(font: font, glyph: glyph)
                        glyphCount += 1
                    }
                } } }
                XCTAssertGreaterThan(glyphCount, 0)
                XCTAssertEqual(SymbolFontIdentity.matrixReadCount, 0)
                XCTAssertEqual(SymbolRunStyle.offsetLookupCount, 0)
                _ = try renderedRow(view)
                XCTAssertEqual(SymbolRunStyle.offsetLookupCount, 0)
            }
        }
        // Positive control: cold fitted-font construction really does exercise the counter.
        let plain = try view(text: "\u{F09B}")
        SymbolFontIdentity.resetMatrixReadCount()
        SymbolRunStyle.resetOffsetLookupCount()
        _ = info(plain)
        XCTAssertGreaterThan(SymbolFontIdentity.matrixReadCount, 0)
        XCTAssertGreaterThan(SymbolRunStyle.offsetLookupCount, 0)
    }

    private func metalOrdinaryGlyphs(_ row: [MetalTerminalRenderer.ShapedSegment], cellWidth: CGFloat)
        -> [(glyph: CGGlyph, font: CTFont, position: CGPoint)] {
        var result: [(glyph: CGGlyph, font: CTFont, position: CGPoint)] = []
        for segment in row {
            var processed = 0
            for run in segment.runs {
                let x = CGFloat(run.startColumn(segment: segment.segment, processedGlyphs: processed)) * cellWidth
                    - run.shaperRun.firstX + (run.sourceColumnOffset ?? 0)
                if run.symbol == nil {
                    for glyphRun in run.shaperRun.glyphRuns where CTFontCopyPostScriptName(glyphRun.font) as String != "LastResort" {
                        for (glyph, point) in zip(glyphRun.glyphs, glyphRun.positions) {
                            result.append((glyph, glyphRun.font, CGPoint(x: point.x + x, y: point.y)))
                        }
                    }
                }
                processed += run.shaperRun.glyphCount
            }
        }
        return result
    }

    private func renderedRow(_ view: TerminalView, expectsInk: Bool = true) throws -> (ink: CGRect, pixels: [UInt8]) {
        let scale = view.backingScaleFactor()
        let marginPixels = 4
        let margin = CGFloat(marginPixels) / scale
        let width = Int(ceil(view.bounds.width * scale)) + marginPixels * 2
        let height = Int(ceil(view.bounds.height * scale)) + marginPixels * 2
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: margin, y: margin)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            view.drawTerminalContents(dirtyRect: view.bounds, context: context, bufferOffset: 0)
            NSGraphicsContext.restoreGraphicsState()
        }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            if bytes[i] > 0 || bytes[i + 1] > 0 || bytes[i + 2] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        } }
        if expectsInk { XCTAssertGreaterThanOrEqual(maxX, minX) }
        return (CGRect(x: CGFloat(minX - marginPixels) / scale, y: CGFloat(minY - marginPixels) / scale,
                       width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale), bytes)
    }
}
#endif
