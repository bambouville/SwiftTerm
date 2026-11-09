//
//  WrapFlagTests.swift
//
//  A row's wrap flag says whether it goes on with the line above it. The
//  reflow joins lines by it, and copy and search read lines by it.
//
import Foundation
import Testing

@testable import SwiftTerm

final class WrapFlagTests {
    private func text(_ line: BufferLine) -> String {
        line.translateToString(trimRight: true, skipNullCellsFollowingWide: true)
    }

    /// Once the scrollback is full, each new row reuses the oldest one, which
    /// kept its own flag: short lines after wrapped ones read as wrapped, and
    /// real wraps after short ones lost theirs.
    @Test func testARecycledRowTakesTheNewRowsWrapFlag() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 10)
        for _ in 0..<20 { t.feed(text: String(repeating: "w", count: 25) + "\r\n") }
        for i in 0..<12 { t.feed(text: "s\(i)\r\n") }
        let lines = t.buffer.lines
        #expect(lines.count == lines.maxLength, "the scrollback must be full")
        let short = (0..<lines.count).filter { text(lines[$0]).hasPrefix("s") }
        #expect(short.count >= 10)
        for index in short {
            #expect(!lines[index].isWrapped, "row \(index): \(text(lines[index]))")
        }

        t.feed(text: String(repeating: "x", count: 25) + "\r\n")
        let long = (0..<lines.count).filter { text(lines[$0]).hasPrefix("x") }
        #expect(long.count == 3)
        #expect(long.map { lines[$0].isWrapped } == [false, true, true])
    }

    /// A wrap above the bottom of the screen flagged a row counted from the
    /// oldest one in the scrollback, not the screen's next row, whether the
    /// row was ASCII or not.
    @Test func testAWrapOnTheScreenFlagsTheScreensNextRow() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 20)
        for i in 0..<12 { t.feed(text: "h\(i)\r\n") }
        t.feed(text: "\u{1b}[H\u{1b}[2J" + String(repeating: "a", count: 15) + "\r\n"
            + String(repeating: "é", count: 15))
        let b = t.buffer
        #expect(b.yBase > 4, "the wrap must happen with history above the screen")
        #expect(!b.lines[b.yBase].isWrapped)
        #expect(b.lines[b.yBase + 1].isWrapped)
        #expect(!b.lines[b.yBase + 2].isWrapped)
        #expect(b.lines[b.yBase + 3].isWrapped)
        for index in 0..<b.yBase {
            #expect(!b.lines[index].isWrapped, "history row \(index) must keep its flag")
        }
    }

    /// Erasing through the end of the cursor's row unwraps the screen's next
    /// row, not a row counted from the oldest one in the scrollback.
    @Test func testAnEraseAboveUnwrapsTheScreensNextRow() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 20)
        t.feed(text: String(repeating: "q", count: 15) + "\r\n")
        for i in 0..<12 { t.feed(text: "h\(i)\r\n") }
        t.feed(text: "\u{1b}[H\u{1b}[2J" + String(repeating: "b", count: 15))
        let b = t.buffer
        #expect(b.lines[1].isWrapped, "the oldest line wraps")
        #expect(b.lines[b.yBase + 1].isWrapped)
        t.feed(text: "\u{1b}[1;10H\u{1b}[1J")
        #expect(!b.lines[b.yBase + 1].isWrapped, "the erase took the line the next row went on with")
        #expect(b.lines[1].isWrapped, "the scrollback keeps its lines")

        // On the last row there is no next row to unwrap.
        t.feed(text: "\u{1b}[5;10H\u{1b}[1J")
        #expect(b.lines.count == b.yBase + b.rows)
    }

    /// Widening joins a line whose first row wrapped a wide character that
    /// its last cell couldn't hold. It measured that row from the buffer's
    /// first rows instead, and left a blank cell where the line wrapped.
    @Test func testWideningJoinsALineThatWrappedAWideCharacter() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 20)
        t.feed(text: "x\r\n" + String(repeating: "a", count: 9) + "中bb\r\n\r\n")
        let b = t.buffer
        #expect(b.lines[2].isWrapped, "the wide character must wrap")
        t.resize(cols: 20, rows: 5)
        let joined = (0..<t.buffer.lines.count).map { text(t.buffer.lines[$0]) }
        #expect(joined.contains(String(repeating: "a", count: 9) + "中bb"), "\(joined)")
    }
}
