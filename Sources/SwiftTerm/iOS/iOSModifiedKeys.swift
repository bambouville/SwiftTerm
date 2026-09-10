//
//  iOSModifiedKeys.swift
//
//  xterm's modified-key encodings for the special keys.
//
//  `pressesBegan` matches the arrows, Home/End, Delete Forward and the
//  function keys on `UIKey.keyCode` alone, so whatever modifiers were held are
//  dropped before anything is sent: ⇧↑ and a bare ↑ both put `ESC [ A` on the
//  wire, and the application has no way to tell them apart. Every other
//  terminal — xterm, iTerm2, Terminal.app — sends `ESC [ 1;2 A` for the first,
//  and TUIs read it.
//
//  Only *modified* presses are encoded here. An unmodified key keeps the
//  existing path untouched, so nothing that works today changes shape.
//
#if os(iOS) || os(visionOS)
import UIKit

enum ModifiedSpecialKey {
    /// xterm's modifier parameter: 1 + Shift + 2·Alt + 4·Control.
    static func parameter(for flags: UIKeyModifierFlags) -> Int {
        var value = 1
        if flags.contains(.shift) { value += 1 }
        if flags.contains(.alternate) { value += 2 }
        if flags.contains(.control) { value += 4 }
        return value
    }

    /// The bytes a modified special key sends, or nil when this key press is
    /// none of this code's business — no modifiers held, a key with no
    /// modified form, or Option on a horizontal arrow, which stays meta
    /// word-motion.
    ///
    /// - Parameter optionAsMetaKey: mirrors `TerminalView.optionAsMetaKey`.
    ///   When it is on, ⌥← / ⌥→ are `ESC b` / `ESC f`, which is what readline
    ///   binds; re-encoding them as `CSI 1;3 D` would break word jumps in
    ///   every shell. Any *other* modifier alongside Option is unambiguous and
    ///   is encoded normally, so ⌥⇧← is `CSI 1;4 D` rather than a shift-less
    ///   `ESC b`.
    static func sequence(for key: UIKey, optionAsMetaKey: Bool) -> [UInt8]? {
        let held = key.modifierFlags.intersection([.shift, .alternate, .control])
        guard !held.isEmpty else { return nil }

        switch key.keyCode {
        case .keyboardLeftArrow, .keyboardRightArrow:
            if optionAsMetaKey && held == .alternate { return nil }
        default:
            break
        }

        let parameter = parameter(for: held)
        if let final = csiFinalByte(for: key.keyCode) {
            return [0x1B, 0x5B, 0x31, 0x3B] + digits(parameter) + [final]
        }
        if let number = tildeNumber(for: key.keyCode) {
            return [0x1B, 0x5B] + digits(number) + [0x3B] + digits(parameter) + [0x7E]
        }
        return nil
    }

    /// Keys whose modified form is `CSI 1 ; <parameter> <final>`.
    private static func csiFinalByte(for keyCode: UIKeyboardHIDUsage) -> UInt8? {
        switch keyCode {
        case .keyboardUpArrow:    return 0x41
        case .keyboardDownArrow:  return 0x42
        case .keyboardRightArrow: return 0x43
        case .keyboardLeftArrow:  return 0x44
        case .keyboardHome:       return 0x48
        case .keyboardEnd:        return 0x46
        case .keyboardF1:         return 0x50
        case .keyboardF2:         return 0x51
        case .keyboardF3:         return 0x52
        case .keyboardF4:         return 0x53
        default:                  return nil
        }
    }

    /// Keys whose modified form is `CSI <number> ; <parameter> ~`.
    ///
    /// Page Up / Page Down are deliberately absent: outside application-cursor
    /// mode this view scrolls its own scrollback with them, and ⇧PageUp *is*
    /// xterm's scrollback binding, so encoding them would take a working
    /// gesture away to hand the application a sequence it rarely binds.
    private static func tildeNumber(for keyCode: UIKeyboardHIDUsage) -> Int? {
        switch keyCode {
        case .keyboardDeleteForward: return 3
        case .keyboardF5:            return 15
        case .keyboardF6:            return 17
        case .keyboardF7:            return 18
        case .keyboardF8:            return 19
        case .keyboardF9:            return 20
        case .keyboardF10:           return 21
        case .keyboardF11:           return 23
        case .keyboardF12:           return 24
        default:                     return nil
        }
    }

    private static func digits(_ number: Int) -> [UInt8] {
        Array(String(number).utf8)
    }
}
#endif
