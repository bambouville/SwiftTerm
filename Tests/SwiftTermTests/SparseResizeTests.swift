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

        for row in 0..<24 {
            terminal.feed(text: "row-\(row)\r\n")
        }

        #expect(terminal.buffer.lines.count > terminal.rows)
        terminal.feed(text: "\(esc)[3J")
        #expect(terminal.buffer.lines.count == terminal.rows)

        let materializedBeforeResize = terminal.buffer.lines.getArray().compactMap { $0 }
        #expect(materializedBeforeResize.count > terminal.buffer.lines.count)
        #expect(materializedBeforeResize.allSatisfy { $0.count == 80 })

        terminal.resize(cols: 120, rows: 4)

        let materializedAfterResize = terminal.buffer.lines.getArray().compactMap { $0 }
        #expect(materializedAfterResize.count == materializedBeforeResize.count)
        #expect(materializedAfterResize.allSatisfy { $0.count == 120 })
    }

    @Test func marginLineOperationsAreSafeAfterClearScrollbackAndGrow() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(
            cols: 80,
            rows: 4,
            scrollback: 32
        )

        for row in 0..<24 {
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
        #expect(
            terminal.buffer.lines.getArray().compactMap { $0 }.allSatisfy { $0.count == 120 }
        )
    }
}
