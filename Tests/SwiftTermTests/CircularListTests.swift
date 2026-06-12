import Testing
@testable import SwiftTerm

final class CircularListTests {

    @Test func testTrimStartRemovesFromFront() {
        let list = CircularList<Int>(maxLength: 10)
        for i in 0..<5 {
            list.push(i)
        }

        list.trimStart(count: 2)

        #expect(list.count == 3)
        #expect(list[0] == 2)
        #expect(list[1] == 3)
        #expect(list[2] == 4)
    }

    /// Over-trimming must clamp to empty: trimStart used to advance
    /// startIndex by the clamped amount but subtract the unclamped argument
    /// from count, leaving a negative count that silently corrupts all
    /// subsequent index math (the count setter only checks the upper bound).
    @Test func testTrimStartClampsWhenCountExceedsLength() {
        let list = CircularList<Int>(maxLength: 10)
        for i in 0..<5 {
            list.push(i)
        }

        list.trimStart(count: 99)

        #expect(list.count == 0)

        // The list must remain usable after the over-trim
        list.push(42)
        #expect(list.count == 1)
        #expect(list[0] == 42)
    }

    /// Non-positive counts are no-ops: a negative count used to rewind
    /// startIndex and inflate the internal count with phantom elements.
    @Test func testTrimStartIgnoresNonPositiveCounts() {
        let list = CircularList<Int>(maxLength: 10)
        for i in 0..<5 {
            list.push(i)
        }

        list.trimStart(count: 0)
        list.trimStart(count: -3)

        #expect(list.count == 5)
        #expect(list[0] == 0)
        #expect(list[4] == 4)
    }

    @Test func testBufferLineListTrimStartClampsWhenCountExceedsLength() {
        let list = CircularBufferLineList(maxLength: 10)
        for _ in 0..<5 {
            list.push(BufferLine(cols: 4, fillData: CharData.Null))
        }

        list.trimStart(count: 99)

        #expect(list.count == 0)
        #expect(list.isEmpty)

        // The list must remain usable after the over-trim
        let line = BufferLine(cols: 4, fillData: CharData.Null)
        list.push(line)
        #expect(list.count == 1)
        #expect(list[0] === line)
    }
}
