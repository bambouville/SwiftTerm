#if os(macOS) || os(iOS) || os(visionOS)
import CoreText
import Foundation

let SwiftTermSymbolXOffsetKey = NSAttributedString.Key("SwiftTermSymbolXOffset")
let SwiftTermSymbolCellKey = NSAttributedString.Key("SwiftTermSymbolCell")

struct SymbolCell: Hashable {
    let column: Int
    let columns: Int
    let sourceColumn: Int
}

let SwiftTermSymbolIdentityKey = NSAttributedString.Key("SwiftTermSymbolIdentity")

/// Matrix inspection happens once when a fitted font is created, never on a Metal cache hit.
struct SymbolFontIdentity: Hashable {
    let a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat
    static private(set) var matrixReadCount = 0

    static func resetMatrixReadCount() { matrixReadCount = 0 }

    init(_ font: CTFont) {
        Self.matrixReadCount += 1
        let matrix = CTFontGetMatrix(font)
        a = matrix.a; b = matrix.b; c = matrix.c; d = matrix.d
        tx = matrix.tx; ty = matrix.ty
    }
}

let SwiftTermSymbolOffsetKey = NSAttributedString.Key("SwiftTermSymbolOffset")
let SwiftTermSymbolOriginalFontKey = NSAttributedString.Key("SwiftTermSymbolOriginalFont")

/// Captured once for a substituted run; ordinary drawing never reads symbol offsets.
struct SymbolRunStyle {
    let offsetX: CGFloat
    let offsetY: CGFloat
    let identity: SymbolFontIdentity
    let separator: Bool
    let cell: SymbolCell
    let font: TTFont
    let originalFont: TTFont
    static private(set) var offsetLookupCount = 0
    static func resetOffsetLookupCount() { offsetLookupCount = 0 }

    static func lookup(_ symbols: [Int: SymbolRunStyle], at index: Int) -> SymbolRunStyle? {
        guard !symbols.isEmpty else { return nil }
        offsetLookupCount += 1
        return symbols[index]
    }

    func applying(to attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = attributes
        result[.font] = font
        result[SwiftTermSymbolOriginalFontKey] = originalFont
        result[SwiftTermSymbolXOffsetKey] = offsetX
        result[SwiftTermSymbolOffsetKey] = offsetY
        result[SwiftTermSymbolIdentityKey] = identity
        result[SwiftTermSymbolCellKey] = cell
        return result
    }

    init(attributes: [NSAttributedString.Key: Any], codePoint: Int) {
        Self.offsetLookupCount += 2
        offsetX = attributes[SwiftTermSymbolXOffsetKey] as? CGFloat ?? 0
        offsetY = attributes[SwiftTermSymbolOffsetKey] as? CGFloat ?? 0
        identity = attributes[SwiftTermSymbolIdentityKey] as! SymbolFontIdentity
        font = attributes[.font] as! TTFont
        originalFont = attributes[SwiftTermSymbolOriginalFontKey] as! TTFont
        separator = TerminalSymbolFallback.isSeparator(codePoint)
        cell = attributes[SwiftTermSymbolCellKey] as? SymbolCell ?? SymbolCell(column: 0, columns: 1, sourceColumn: 0)
    }
}

/// Coverage is tested on the face itself, never CoreText's fallback chain.
final class TerminalSymbolFontCache {
    private struct CursorRow {
        let row: Int
        let columns: Int
        let cellSize: CGSize
        let deviceScale: CGFloat
        let customBlocks: Bool
        let cells: [CharData]
        let characters: [Int: Character]
        let symbols: [Int: SymbolRunStyle]
    }
    // One native caret per view: retain only its latest resolved row.
    private var cursorRow: CursorRow?
    private(set) var cursorRowBuildCount = 0

    func cursorStyles(row: Int, line: BufferLine, columns: Int, cellSize: CGSize,
                      deviceScale: CGFloat, customBlocks: Bool,
                      character: (CharData) -> Character) -> [Int: SymbolRunStyle]? {
        guard let cached = cursorRow, cached.row == row, cached.columns == columns,
              cached.cellSize == cellSize, cached.deviceScale == deviceScale,
              cached.customBlocks == customBlocks, cached.cells.count == line.count else { return nil }
        for column in 0..<line.count {
            let old = cached.cells[column], current = line[column]
            guard old.code == current.code, old.width == current.width, old.attribute == current.attribute,
                  old.payload.code == current.payload.code else { return nil }
            if current.code >= CharData.maxRune, cached.characters[column] != character(current) { return nil }
        }
        return cached.symbols
    }

    func rememberCursorRow(row: Int, line: BufferLine, columns: Int, cellSize: CGSize,
                           deviceScale: CGFloat, customBlocks: Bool, symbols: [Int: SymbolRunStyle],
                           character: (CharData) -> Character) {
        var characters: [Int: Character] = [:]
        for column in 0..<line.count where line[column].code >= CharData.maxRune {
            characters[column] = character(line[column])
        }
        cursorRow = CursorRow(row: row, columns: columns, cellSize: cellSize, deviceScale: deviceScale,
            customBlocks: customBlocks, cells: line.getData(), characters: characters, symbols: symbols)
        cursorRowBuildCount += 1
    }

    private struct CoverageKey: Hashable {
        let font: ObjectIdentifier
        let codePoint: UInt32
    }
    private struct FontKey: Hashable {
        let scaleX: CGFloat
        let scaleY: CGFloat
    }
    private struct Metrics {
        let advance: CGFloat
        let ink: CGRect
    }
    private struct FittedFont {
        let font: TTFont
        let identity: SymbolFontIdentity
    }
    private var coverage = SymbolCache<CoverageKey, Bool>()
    private var selectedCharacters: [ObjectIdentifier: (TTFont, CFCharacterSet)] = [:]
    private var metrics = SymbolCache<UInt32, Metrics>()
    private var fonts = SymbolCache<FontKey, FittedFont>()
    private var source: CTFont?
    private var sourceCharacters: CFCharacterSet?

    var entryCounts: [Int] { [coverage.count, metrics.count, fonts.count] }
    private(set) var selectedCharacterSetCopyCount = 0

    func reset() {
        cursorRow = nil
        cursorRowBuildCount = 0
        coverage.removeAll(keepingCapacity: true)
        fonts.removeAll(keepingCapacity: true)
        metrics.removeAll(keepingCapacity: true)
        selectedCharacterSetCopyCount = 0
        selectedCharacters.removeAll(keepingCapacity: true)
        source = nil
        sourceCharacters = nil
    }

    func resolve(codePoint: UInt32, scalarCount: Int, selected: TTFont, symbols: TTFont, pointSize: CGFloat,
                 columns: Int, nextCellExists: Bool, nextCellIsBlank: Bool,
                 cellSize: CGSize, baseline: CGFloat, deviceScale: CGFloat)
        -> (font: TTFont, offset: CGFloat, offsetX: CGFloat, identity: SymbolFontIdentity)? {
        // Cheap eligibility check also keeps grapheme cells out of the coverage cache.
        guard TerminalSymbolFallback.shouldSubstitute(codePoint: Int(codePoint), scalarCount: scalarCount,
            ownFaceHasGlyph: false, symbolsFaceHasGlyph: true) else { return nil }
        if source == nil {
            var matrix = CGAffineTransform.identity
            source = CTFontCreateCopyWithAttributes(symbols as CTFont, pointSize, &matrix, nil)
            sourceCharacters = CTFontCopyCharacterSet(source!)
        }
        let key = CoverageKey(font: ObjectIdentifier(selected), codePoint: codePoint)
        let substitute: Bool
        if let cached = coverage[key] {
            substitute = cached
        } else {
            let face = ObjectIdentifier(selected)
            let characters: CFCharacterSet
            if let cached = selectedCharacters[face] { characters = cached.1 }
            else {
                selectedCharacterSetCopyCount += 1
                characters = CTFontCopyCharacterSet(selected as CTFont)
                selectedCharacters[face] = (selected, characters)
            }
            substitute = TerminalSymbolFallback.shouldSubstitute(codePoint: Int(codePoint), scalarCount: scalarCount,
                ownFaceHasGlyph: CFCharacterSetIsLongCharacterMember(characters, codePoint),
                symbolsFaceHasGlyph: CFCharacterSetIsLongCharacterMember(sourceCharacters!, codePoint))
            coverage[key] = substitute
        }
        guard substitute, let source else { return nil }
        let glyphMetrics: Metrics
        if let cached = metrics[codePoint] {
            glyphMetrics = cached
        } else {
            let text = Array(String(UnicodeScalar(codePoint)!).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: text.count)
            CTFontGetGlyphsForCharacters(source, text, &glyphs, text.count)
            var glyph = glyphs.first(where: { $0 != 0 }) ?? 0
            var size = CGSize.zero
            CTFontGetAdvancesForGlyphs(source, .default, &glyph, &size, 1)
            // Font bounding rectangles include off-curve controls; fit the actual outline.
            let ink = CTFontCreatePathForGlyph(source, glyph, nil)?.boundingBoxOfPath ?? .zero
            glyphMetrics = Metrics(advance: glyph == 0 ? 0 : size.width, ink: ink)
            metrics[codePoint] = glyphMetrics
        }
        guard glyphMetrics.advance > 0 else { return nil }
        let ink = glyphMetrics.ink.isNull ? CGRect.zero : glyphMetrics.ink
        let layout = TerminalSymbolFallback.layout(codePoint: Int(codePoint), columns: columns,
            nextCellExists: nextCellExists, nextCellIsBlank: nextCellIsBlank,
            cellWidth: cellSize.width, cellHeight: cellSize.height, advance: glyphMetrics.advance,
            ascent: CTFontGetAscent(source), descent: CTFontGetDescent(source),
            inkMinX: ink.minX, inkMinY: ink.minY, inkMaxX: ink.maxX, inkMaxY: ink.maxY,
            bleed: TerminalSymbolFallback.SEPARATOR_BLEED_DEVICE_PIXELS / max(1, deviceScale))
        let fontKey = FontKey(scaleX: layout.scaleX, scaleY: layout.scaleY)
        let fitted: FittedFont
        if let cached = fonts[fontKey] {
            fitted = cached
        } else {
            var matrix = CGAffineTransform(scaleX: layout.scaleX, y: layout.scaleY)
            let font = CTFontCreateCopyWithAttributes(source, pointSize, &matrix, nil) as TTFont
            fitted = FittedFont(font: font, identity: SymbolFontIdentity(font as CTFont))
            fonts[fontKey] = fitted
        }
        return (fitted.font, layout.baseline - baseline, layout.offsetX, fitted.identity)
    }
}
#endif
