//
//  TrimNotificationTests.swift
//
//  Front-ends keep a reader and a selection on their rows by the rows the
//  shown buffer drops from its top: every dropped row is reported, and only
//  the shown buffer's.
//
import Foundation
import Testing

@testable import SwiftTerm

final class TrimNotificationTests {
    /// A scroll region whose bottom margin is above the last row inserts the
    /// new row by splicing, and a full list drops its oldest row to make
    /// room: mosh repaints a prompt or input box this way under scrolling
    /// output. The dropped rows went unreported.
    @Test func testAScrollRegionAboveTheLastRowReportsTheRowsItDrops() {
        let (t, d) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 3)
        for i in 0..<20 { t.feed(text: "l\(i)\r\n") }
        #expect(t.buffer.lines.count == t.buffer.lines.maxLength, "the scrollback must be full")
        let trimmed = d.trimmedCounts.reduce(0, +)
        #expect(trimmed > 0, "plain output reports its trims")
        let oldest = t.buffer.lines[0].translateToString(trimRight: true)

        #expect(d.trimsKeptFrom.allSatisfy { $0 == nil }, "plain output moves every row")

        // Rows 1-4 scroll; row 5, below the margin, keeps its place.
        t.feed(text: "\u{1b}[5;1HPINNED\u{1b}[1;4r\u{1b}[4;1H" + "a\nb\nc\n")
        #expect(d.trimmedCounts.reduce(0, +) == trimmed + 3)
        #expect(t.buffer.lines[0].translateToString(trimRight: true) != oldest)
        let pinned = t.buffer.yBase + 4
        #expect(t.buffer.lines[pinned].translateToString(trimRight: true) == "PINNED")
        #expect(Array(d.trimsKeptFrom.suffix(3)) == [pinned, pinned, pinned])
        #expect(t.trimKeepsRowsFrom == nil, "only during the report")
    }

    /// A selection moves with the rows a trim moved: on a pinned prompt below
    /// a scroll region it stays, in the region it goes up with the text.
    /// With room to spare the same region moves the rows below its margin
    /// down under the new row instead, and says where; plain output only
    /// appends.
    @Test func testAScrollRegionWithRoomReportsWhereItInserts() {
        let (t, d) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 100)
        for i in 0..<20 { t.feed(text: "l\(i)\r\n") }
        #expect(d.insertions.isEmpty, "plain output appends")
        t.feed(text: "\u{1b}[5;1HPINNED\u{1b}[1;4r\u{1b}[4;1H" + "a\nb\nc\n")
        #expect(d.trimmedCounts.isEmpty, "the scrollback has room")
        let base = t.buffer.yBase
        #expect(d.insertions.map(\.row) == [base + 1, base + 2, base + 3])
        #expect(d.insertions.allSatisfy { $0.count == 1 })
        #expect(t.buffer.lines[base + 4].translateToString(trimRight: true) == "PINNED")
    }

    @Test func testASelectionKeepsThePinnedRowsAndFollowsTheScrolledOnes() {
        let (t, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 5, scrollback: 3)
        for i in 0..<20 { t.feed(text: "l\(i)\r\n") }
        #expect(t.buffer.lines.count == 8, "selections clamp to the buffer's rows")
        let selection = SelectionService(terminal: t)
        selection.setSelection(start: Position(col: 2, row: 7), end: Position(col: 5, row: 7))
        selection.shiftRows(by: -1, keptFrom: 7)
        #expect(selection.start == Position(col: 2, row: 7) && selection.end == Position(col: 5, row: 7))

        selection.setSelection(start: Position(col: 0, row: 4), end: Position(col: 3, row: 7))
        selection.shiftRows(by: -1, keptFrom: 7)
        #expect(selection.start == Position(col: 0, row: 3) && selection.end == Position(col: 3, row: 7))

        selection.setSelection(start: Position(col: 0, row: 4), end: Position(col: 3, row: 7))
        selection.shiftRows(by: -1)
        #expect(selection.start == Position(col: 0, row: 3) && selection.end == Position(col: 3, row: 6))
    }

    /// A resize trims both buffers; the hidden one's trim moves nothing a
    /// front-end shows. A program that left the alternate screen without
    /// clearing it (mode 47) kept its cursor on that screen's last row, so
    /// shrinking trimmed that screen's top while the shell's was shown, and
    /// the shown screen's reader and selection moved by those rows.
    @Test func testOnlyTheShownBuffersTrimsAreReported() {
        let (t, d) = TerminalTestHarness.makeTerminal(cols: 10, rows: 10, scrollback: 20)
        t.feed(text: "\u{1b}[?47h\u{1b}[10;1Hbottom\u{1b}[?47l\u{1b}[H")
        #expect(!t.isCurrentBufferAlternate)
        #expect(t.altBuffer.y == 9, "the alternate screen keeps its cursor on its last row")
        t.resize(cols: 10, rows: 5)
        #expect(d.trimmedCounts.isEmpty, "\(d.trimmedCounts)")

        // The shown alternate screen's own trims are still reported.
        t.feed(text: "\u{1b}[?47h\u{1b}[5;1H")
        t.resize(cols: 10, rows: 3)
        #expect(!d.trimmedCounts.isEmpty)
    }

    /// The other way round: a full-screen program is shown while the shell's
    /// full scrollback, cursor on its last row, trims on a shrink.
    @Test func testTheHiddenShellsTrimsAreNotReported() {
        let (t, d) = TerminalTestHarness.makeTerminal(cols: 10, rows: 10, scrollback: 5)
        for i in 0..<30 { t.feed(text: "l\(i)\r\n") }
        #expect(t.buffer.lines.count == t.buffer.lines.maxLength, "the scrollback must be full")
        t.feed(text: "\u{1b}[?47h\u{1b}[H")
        #expect(t.isCurrentBufferAlternate)
        let before = d.trimmedCounts
        t.resize(cols: 10, rows: 5)
        #expect(d.trimmedCounts == before, "\(d.trimmedCounts)")
    }
}
