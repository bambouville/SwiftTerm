import Foundation
import Testing
@testable import SwiftTerm

final class LiveScreenSnapshotTests {
    @Test func historyIndependentSnapshotUsesLiveRowsAndPreservesScrollPosition() throws {
        var expected: Terminal.LiveScreenSnapshot?
        var expectedCellStorage: Int?
        for history in [0, 10_000, 100_000] {
            let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24, scrollback: 100_024)
            for _ in 0..<history { terminal.feed(text: "past output\r\n") }
            terminal.feed(text: "\u{1b}[2J\u{1b}[Hlive\r\n❯ \u{1b}[2msuggestion\u{1b}[0m\u{1b}[2;3H")
            terminal.buffer.yDisp = 0
            let before = terminal.buffer.yDisp
            let oldExportBytes = terminal.getBufferAsData().count
            let started = Date()
            let snapshot = try terminal.liveScreenSnapshot().get()
            let elapsed = Date().timeIntervalSince(started)
            #expect(terminal.buffer.yDisp == before)
            #expect(snapshot.visitedCells == 80 * 24)
            #expect(snapshot.cells.count == 80 * 24)
            #expect(snapshot.textUTF8Bytes == expected?.textUTF8Bytes ?? snapshot.textUTF8Bytes)
            if let expected { #expect(snapshot == expected) } else { expected = snapshot }
            let allocatedCellBytes = snapshot.cells.capacity * MemoryLayout<Terminal.LiveScreenSnapshot.Cell>.stride
            #expect(allocatedCellBytes <= 2 * 80 * 24 * MemoryLayout<Terminal.LiveScreenSnapshot.Cell>.stride)
            if let expectedCellStorage { #expect(allocatedCellBytes == expectedCellStorage) }
            else { expectedCellStorage = allocatedCellBytes }
            print("LIVE_SNAPSHOT cellStorage=\(allocatedCellBytes) history=\(history) visited=\(snapshot.visitedCells) utf8=\(snapshot.textUTF8Bytes) oldExport=\(oldExportBytes) seconds=\(elapsed)")
        }
    }

    @Test func snapshotOwnsCellsAndPreservesWidthStyleWrapAndBufferIdentity() throws {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 3, scrollback: 8)
        terminal.feed(text: "\u{1b}[2m界e\u{301}😀abcZQ\u{1b}[0m")
        let primary = try terminal.liveScreenSnapshot().get()
        #expect(primary.isAlternate == false)
        #expect(primary.wrappedRows == [false, true, false])
        #expect(primary.cells[0].width == 2)
        #expect(primary.cells[1].width == 0)
        #expect(primary.cells[2].text == "e\u{301}")
        #expect(primary.cells[0].attribute.style.contains(.dim))
        terminal.feed(text: "\u{1b}[?1049hOTHER\u{1b}[?25l")
        let alternate = try terminal.liveScreenSnapshot().get()
        #expect(alternate.isAlternate)
        #expect(alternate.cursorVisible == false)
        #expect(primary.cells[0].text == "界") // detached from recycled mutable lines
        terminal.feed(text: "\u{1b}[?1049l")
        #expect(try terminal.liveScreenSnapshot().get().cells == primary.cells)
    }

    @Test func incompleteFramesAndOversizedCapturesFailWithoutPlainFallback() throws {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        #expect(terminal.liveScreenSnapshot(limits: .init(maximumCells: 1919, maximumTextUTF8Bytes: 65_536)) == .failure(.cellLimit))
        #expect(terminal.liveScreenSnapshot(limits: .init(maximumCells: 1920, maximumTextUTF8Bytes: 1919)) == .failure(.textLimit))
        terminal.feed(text: "\u{1b}[?2026hpartial")
        #expect(terminal.liveScreenSnapshot() == .failure(.incompleteFrame))
        terminal.feed(text: "\u{1b}[?2026l")
        #expect(try terminal.liveScreenSnapshot().get().cells[0].text == "p")
    }

    @Test func resizedAndTrimmedSnapshotRemainsBounded() throws {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 12, rows: 4, scrollback: 32)
        for _ in 0..<80 { terminal.feed(text: "old\r\n") }
        terminal.feed(text: "\u{1b}[3J")
        terminal.resize(cols: 20, rows: 6)
        let snapshot = try terminal.liveScreenSnapshot().get()
        #expect(snapshot.columns == 20)
        #expect(snapshot.rows == 6)
        #expect(snapshot.cells.count == 120)
        #expect(snapshot.visitedCells == 120)
    }
}
