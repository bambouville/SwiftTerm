//
//  LiveTailRowsTests.swift
//
//  A frame up to a part row taller than its grid rests on the live tail with
//  that part row above the grid. It draws nothing there: over a full-screen
//  program on the primary screen, the newest history row would show above
//  a program that never wrote it. Metal, hit testing and a frame that
//  shrinks without a new grid keep to the grid too.
//
#if os(iOS)
import Foundation
import Testing
import UIKit

@testable import SwiftTerm

@MainActor
final class LiveTailRowsTests {
    /// A view whose grid leaves `partRow` of a row above it, with history
    /// and a program on the primary screen, at rest on the bounds' clamp.
    private func makeView(partRow: CGFloat) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        view.layoutIfNeeded()
        let cell = view.cellDimension.height
        view.frame.size.height = CGFloat(view.getTerminal().rows) * cell + partRow * cell
        view.layoutIfNeeded()
        view.feed(text: (0..<100).map { "history \($0)\r\n" }.joined() + "\u{1B}[2J\u{1B}[Hprogram")
        view.contentOffset.y = view.contentSize.height - view.bounds.height
        return view
    }

    private func gridTop(_ view: TerminalView) -> Int {
        let buffer = view.terminal.displayBuffer
        return buffer.lines.count - buffer.rows
    }

    /// Metal places rows on whole rows, so the live tail starts the grid at
    /// the top: placed from the part row's history row, the blank would take
    /// a whole row and the grid's last row would show only the part row.
    @Test func testMetalStartsTheLiveTailGridAtTheTop() throws {
        for partRow in [0.3, 0.97] as [CGFloat] {
            let view = makeView(partRow: partRow)
            let buffer = view.terminal.displayBuffer
            let range = try #require(MetalTerminalRenderer.visibleRowRange(
                buffer: buffer, cellHeight: view.cellDimension.height, terminalView: view))
            #expect(range.0 == gridTop(view), "first drawn row, \(partRow) of a row above the grid")
            #expect(range.1 == buffer.lines.count - 1, "last drawn row, \(partRow) of a row above the grid")
            #expect(range.2 == gridTop(view), "row at the top, \(partRow) of a row above the grid")

            // Off the tail, history slides in with the finger as on CoreGraphics.
            view.contentOffset.y -= 1
            let off = try #require(MetalTerminalRenderer.visibleRowRange(
                buffer: buffer, cellHeight: view.cellDimension.height, terminalView: view))
            let underFinger = Int((view.contentOffset.y / view.cellDimension.height).rounded(.down))
            #expect(off.0 == underFinger && off.2 == underFinger && underFinger < gridTop(view),
                    "\(partRow) of a row, a point off the tail")
        }
    }

    /// A touch in the blank part row lands on the grid's first row, not on
    /// the history row it hides; off the tail it lands where it is drawn.
    @Test func testATouchAboveTheLiveTailGridLandsOnItsFirstRow() {
        let view = makeView(partRow: 0.5)
        let top = CGPoint(x: 5, y: view.contentOffset.y + 1)
        #expect(view.calculateTapHit(point: top).grid.row == gridTop(view))
        let inGrid = CGPoint(x: 5, y: CGFloat(gridTop(view) + 2) * view.cellDimension.height + 1)
        #expect(view.calculateTapHit(point: inGrid).grid.row == gridTop(view) + 2)
        view.contentOffset.y -= view.cellDimension.height
        let history = CGPoint(x: 5, y: view.contentOffset.y + 1)
        #expect(view.calculateTapHit(point: history).grid.row < gridTop(view))
    }

    /// A frame that shrinks by less than the part row keeps its grid, and
    /// UIKit leaves the reader where they were, above the new clamp: the
    /// history row would show over the program again until output came.
    @Test func testAShrinkingFrameKeepsTheLiveTailOnTheClamp() {
        let view = makeView(partRow: 0.7)
        let rows = view.terminal.rows
        #expect(!view.drawsHistoryAboveGrid)
        view.frame.size.height -= 0.3 * view.cellDimension.height
        view.layoutIfNeeded()
        #expect(view.terminal.rows == rows, "the grid still fits")
        #expect(abs(view.contentOffset.y - (view.contentSize.height - view.bounds.height)) <= 0.5,
                "the reader is on the new clamp")
        #expect(!view.drawsHistoryAboveGrid)

        // A reader in history stays where they are.
        view.contentOffset.y -= 3 * view.cellDimension.height
        let reading = view.contentOffset.y
        view.frame.size.height -= 0.2 * view.cellDimension.height
        view.layoutIfNeeded()
        #expect(view.contentOffset.y == reading)
    }
}
#endif
