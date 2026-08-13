import Testing

@testable import SwiftTerm

final class SparseResizeTests {
    private let esc = "\u{1b}"

    @Test func resizeWidensMaterializedLinesOutsideLogicalCount() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(
            cols: 80,
            rows: 4,
            scrollback: 32
        )

        // Fill and rotate the complete ring so ED3 leaves materialized lines
        // immediately beyond the new logical end.
        for row in 0..<80 {
            terminal.feed(text: "row-\(row)\r\n")
        }

        #expect(terminal.buffer.lines.count > terminal.rows)
        terminal.feed(text: "\(esc)[3J")
        #expect(terminal.buffer.lines.count == terminal.rows)

        let firstOverflowIndex = terminal.buffer.lines.count
        let overflowBeforeResize = terminal.buffer.lines.materializedLine(at: firstOverflowIndex)
        #expect(overflowBeforeResize?.count == 80)

        terminal.resize(cols: 120, rows: 4)

        #expect(terminal.buffer.lines.materializedLine(at: firstOverflowIndex)?.count == 120)
    }

    @Test func marginLineOperationsAreSafeAfterClearScrollbackAndGrow() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(
            cols: 80,
            rows: 4,
            scrollback: 32
        )

        for row in 0..<80 {
            terminal.feed(text: "row-\(row)\r\n")
        }
        terminal.feed(text: "\(esc)[3J")
        terminal.resize(cols: 120, rows: 4)

        terminal.feed(text: "\(esc)[?69h")
        terminal.feed(text: "\(esc)[1;120s")
        terminal.feed(text: "\(esc)[2;1H")
        terminal.feed(text: "\(esc)[L")
        terminal.feed(text: "\(esc)[M")

        #expect(terminal.getDims().cols == 120)
        #expect(terminal.getDims().rows == 4)
        let reachableLineCount = min(
            terminal.buffer.lines.maxLength,
            terminal.buffer.lines.count + terminal.rows
        )
        for index in 0..<reachableLineCount {
            if let line = terminal.buffer.lines.materializedLine(at: index) {
                #expect(line.count == 120)
            }
        }
    }
}
