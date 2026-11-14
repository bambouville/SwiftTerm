import Foundation

// Keep constants and geometry cases mirrored in Android's TerminalSymbolFallback.
// The shared rule is documented in Tessera's SharedAssets/README.md.
enum TerminalSymbolFallback {
    static let PRIVATE_USE_BMP_START = 0xE000
    static let PRIVATE_USE_BMP_END = 0xF8FF
    static let PRIVATE_USE_PLANE_15_START = 0xF0000
    static let PRIVATE_USE_PLANE_15_END = 0xFFFFD
    static let PRIVATE_USE_PLANE_16_START = 0x100000
    static let PRIVATE_USE_PLANE_16_END = 0x10FFFD
    static let SYMBOL_CACHE_CAPACITY = 1024
    static let SEPARATOR_START = 0xE0B0
    static let SEPARATOR_END = 0xE0D7
    static let SEPARATOR_BLEED_DEVICE_PIXELS: CGFloat = 0.5

    static func isPrivateUse(_ codePoint: Int) -> Bool {
        guard codePoint >= PRIVATE_USE_BMP_START else { return false }
        return codePoint <= PRIVATE_USE_BMP_END
            || (codePoint >= PRIVATE_USE_PLANE_15_START && codePoint <= PRIVATE_USE_PLANE_15_END)
            || (codePoint >= PRIVATE_USE_PLANE_16_START && codePoint <= PRIVATE_USE_PLANE_16_END)
    }

    static func shouldSubstitute(codePoint: Int, scalarCount: Int, ownFaceHasGlyph: Bool,
                                 symbolsFaceHasGlyph: Bool) -> Bool {
        scalarCount == 1 && isPrivateUse(codePoint) && !ownFaceHasGlyph && symbolsFaceHasGlyph
    }

    static func isSeparator(_ codePoint: Int) -> Bool {
        codePoint >= SEPARATOR_START && codePoint <= SEPARATOR_END
    }

    static func allowedCells(columns: Int, nextCellExists: Bool, nextCellIsBlank: Bool) -> Int {
        columns + (nextCellExists && nextCellIsBlank ? 1 : 0)
    }

    struct Layout: Hashable {
        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        /// Baseline measured up from the bottom of the row; descent is positive.
        let baseline: CGFloat
    }

    static func layout(codePoint: Int, columns: Int, nextCellExists: Bool, nextCellIsBlank: Bool,
                       cellWidth: CGFloat, cellHeight: CGFloat, advance: CGFloat,
                       ascent: CGFloat, descent: CGFloat, inkMinX: CGFloat, inkMinY: CGFloat,
                       inkMaxX: CGFloat, inkMaxY: CGFloat, bleed: CGFloat) -> Layout {
        let hasInk = inkMaxX > inkMinX && inkMaxY > inkMinY
        if isSeparator(codePoint) {
            if hasInk {
                let scaleX = (CGFloat(columns) * cellWidth + 2 * bleed) / (inkMaxX - inkMinX)
                let scaleY = (cellHeight + 2 * bleed) / (inkMaxY - inkMinY)
                return Layout(scaleX: scaleX, scaleY: scaleY,
                              offsetX: -bleed - inkMinX * scaleX,
                              baseline: -bleed - inkMinY * scaleY)
            }
            let scaleY = cellHeight / (ascent + descent)
            return Layout(scaleX: CGFloat(columns) * cellWidth / advance,
                          scaleY: scaleY, offsetX: 0, baseline: descent * scaleY)
        }
        let width = CGFloat(allowedCells(columns: columns, nextCellExists: nextCellExists,
                                         nextCellIsBlank: nextCellIsBlank)) * cellWidth
        let boxMinX = hasInk ? min(0, inkMinX) : 0
        let boxMaxX = hasInk ? max(advance, inkMaxX) : advance
        let scale = min(1, width / (boxMaxX - boxMinX))
        return Layout(scaleX: scale, scaleY: scale, offsetX: -boxMinX * scale,
                      baseline: (cellHeight - (ascent - descent) * scale) / 2)
    }
}

/// Terminal input cannot retain an unlimited number of probes or derived fonts.
struct SymbolCache<Key: Hashable, Value> {
    private var values: [Key: Value] = [:]
    var count: Int { values.count }
    subscript(key: Key) -> Value? {
        get { values[key] }
        set {
            if values[key] == nil && values.count >= TerminalSymbolFallback.SYMBOL_CACHE_CAPACITY {
                values.removeAll(keepingCapacity: true)
            }
            values[key] = newValue
        }
    }
    mutating func removeAll(keepingCapacity: Bool = true) { values.removeAll(keepingCapacity: keepingCapacity) }
}
