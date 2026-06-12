//
//  HistoryTests.swift
//  SwiftTerm
//
//  Created for testing the dynamic history size change API
//

import Testing
@testable import SwiftTerm

final class HistoryTests {
    
    class TestDelegate: TerminalDelegate {
        func showCursor(source: Terminal) {}
        func hideCursor(source: Terminal) {}
        func setTerminalTitle(source: Terminal, title: String) {}
        func setTerminalIconTitle(source: Terminal, title: String) {}
        func windowCommand(source: Terminal, command: Terminal.WindowManipulationCommand) -> [UInt8]? { return nil }
        func sizeChanged(source: Terminal) {}
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
        func scrolled(source: Terminal, yDisp: Int) {}
        func linefeed(source: Terminal) {}
        func bufferActivated(source: Terminal) {}
        func bell(source: Terminal) {}
    }
    
    @Test func testChangeHistorySize() {
        let delegate = TestDelegate()
        let options = TerminalOptions(scrollback: 100)
        let terminal = Terminal(delegate: delegate, options: options)
        
        // Test initial scrollback
        #expect(terminal.buffer.scrollback == 100)
        #expect(terminal.buffer.hasScrollback)
        
        // Test increasing history size
        terminal.changeHistorySize(500)
        #expect(terminal.buffer.scrollback == 500)
        #expect(terminal.buffer.hasScrollback)
        #expect(terminal.options.scrollback == 500)
        
        // Test decreasing history size
        terminal.changeHistorySize(50)
        #expect(terminal.buffer.scrollback == 50)
        #expect(terminal.buffer.hasScrollback)
        #expect(terminal.options.scrollback == 50)
        
        // Test disabling scrollback
        terminal.changeHistorySize(nil)
        #expect(terminal.buffer.scrollback == nil)
        #expect(!terminal.buffer.hasScrollback)
        #expect(terminal.options.scrollback == 0)
        
        // Test re-enabling scrollback
        terminal.changeHistorySize(1000)
        #expect(terminal.buffer.scrollback == 1000)
        #expect(terminal.buffer.hasScrollback)
        #expect(terminal.options.scrollback == 1000)
    }

    @Test func testChangeScrollbackApi() {
        let delegate = TestDelegate()
        let options = TerminalOptions(scrollback: 20)
        let terminal = Terminal(delegate: delegate, options: options)

        terminal.changeScrollback(80)
        #expect(terminal.buffer.scrollback == 80)
        #expect(terminal.options.scrollback == 80)

        terminal.changeScrollback(nil)
        #expect(terminal.buffer.scrollback == nil)
        #expect(!terminal.buffer.hasScrollback)
        #expect(terminal.options.scrollback == 0)
    }
    
    @Test func testHistorySizeBufferLength() {
        let delegate = TestDelegate()
        let options = TerminalOptions(cols: 80, rows: 25, scrollback: 100)
        let terminal = Terminal(delegate: delegate, options: options)
        
        let initialMaxLength = terminal.buffer.lines.maxLength
        #expect(initialMaxLength == 125) // 25 rows + 100 scrollback
        
        // Increase history size
        terminal.changeHistorySize(200)
        #expect(terminal.buffer.lines.maxLength == 225) // 25 rows + 200 scrollback
        
        // Decrease history size
        terminal.changeHistorySize(50)
        #expect(terminal.buffer.lines.maxLength == 75) // 25 rows + 50 scrollback
        
        // Disable scrollback
        terminal.changeHistorySize(nil)
        #expect(terminal.buffer.lines.maxLength == 25) // 25 rows only
    }

    /// A cursor saved with DECSC must survive a history-size toggle: savedY
    /// is viewport-relative and the kept viewport rows do not move relative
    /// to the screen when scrollback history is trimmed.
    @Test func testHistorySizeChangePreservesSavedCursor() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 100)
        for i in 0..<20 {
            terminal.feed(text: "line\(i)\r\n")
        }
        #expect(terminal.buffer.yBase > 0)

        terminal.feed(text: "\u{1b}[4;2H") // cursor to row 3, col 1 (0-based)
        terminal.feed(text: "\u{1b}7")     // DECSC
        #expect(terminal.buffer.savedY == 3)

        terminal.changeScrollback(0)
        terminal.changeScrollback(100)

        terminal.feed(text: "\u{1b}8")     // DECRC
        #expect(terminal.buffer.y == 3)
        #expect(terminal.buffer.x == 1)
    }

    /// Same property through the alt-screen path: ?1049h saves the normal
    /// buffer cursor, a scrollback toggle while the alt screen is active must
    /// not corrupt it, and ?1049l restores it to the saved row.
    @Test func testHistorySizeChangePreservesAltScreenSavedCursor() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 100)
        for i in 0..<20 {
            terminal.feed(text: "line\(i)\r\n")
        }

        terminal.feed(text: "\u{1b}[4;2H")    // cursor to row 3, col 1 (0-based)
        terminal.feed(text: "\u{1b}[?1049h")  // save cursor, enter alt screen

        terminal.changeScrollback(0)
        terminal.changeScrollback(100)

        terminal.feed(text: "\u{1b}[?1049l")  // leave alt screen, restore cursor
        #expect(terminal.buffer.y == 3)
        #expect(terminal.buffer.x == 1)
    }
}
