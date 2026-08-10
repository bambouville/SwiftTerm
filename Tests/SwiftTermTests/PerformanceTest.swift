//
//  PerformanceTest.swift
//
//
//  Created by Miguel de Icaza on 4/17/20.
//
#if os(macOS)
import Foundation
import Testing
import os
@testable import SwiftTerm

private final class WeakTerminalReference {
    weak var value: Terminal?

    init(_ value: Terminal) {
        self.value = value
    }
}

final class PerformaceTests {
    let signposter = OSSignposter(subsystem: "SwiftTerm", category: .pointsOfInterest)

    @Test func testPerformance() {
        let h = HeadlessTerminal (queue: SwiftTermTests.queue) { exitCode in }
        let t = h.terminal!

        // 5.164 before the changes
        t.feed (text: "\u{1b}[38;2;19;49;174;48;2;23;56;179mStringThis is a very long line\n\r")
        for _ in 0..<20000 {
            t.feed(text: "pointless repetition\n")
        }
    }

    @Test func testPerformance2() {
        testFeed(
            tag: "insertCharacter",
            data: [UInt8]("pointless repetition\n".utf8),
            duration: Duration(secondsComponent: 10, attosecondsComponent: 0))
    }

    func testFeed(tag: StaticString, data: [UInt8], duration: Duration) {
        let h = HeadlessTerminal (queue: SwiftTermTests.queue) { exitCode in }
        let t = h.terminal!

        var now = ContinuousClock.now
        var outerIterations = 0
        let interval = signposter.beginInterval(tag)
        let start = ContinuousClock.now

        t.feed (text: "\u{1b}[38;2;19;49;174;48;2;23;56;179mStringThis is a very long line\n\r")

        repeat {
            t.feed(byteArray: data)
            outerIterations += 1
            now = .now
        } while (start.duration(to: now) < duration)
        let elapsed = start.duration(to: now)
        let attoseconds = Double(elapsed.components.attoseconds)
        let seconds = Double(elapsed.components.seconds)
        let throughput = Double(outerIterations) / (seconds + attoseconds / 1e18)
        signposter.endInterval(tag, interval, "\(throughput) throughput calls/s")
        print("\(tag): \(throughput) throughput calls/s")
    }

    @Test func measureBigBlogFeed() {
        guard let d = try? Data(contentsOf: URL(filePath: "/Users/miguel/cvs/vtebench/x")) else {
            print("Skipping test, we do not have the data")
            return
        }
        let h = HeadlessTerminal (queue: SwiftTermTests.queue) { exitCode in }
        let t = h.terminal!

        let internval = signposter.beginInterval("FeedPerf")
        let start = ContinuousClock.now

        for _ in 0..<10 {
            t.feed(byteArray: [UInt8](d))
        }

        let elapsed = start.duration(to: ContinuousClock.now)
        signposter.endInterval("FeedPerf", internval, "Time \(elapsed)")
        print("measureBigBlogFeed: \(elapsed) elapsed")

    }

    @Test func repeatBigBlob() {
        // This file is generated with:
        // vtebench:
        // target/release/vtebench --max-samples 1 -b benchmarks/medium_cells/
        guard let d = try? Data(contentsOf: URL(filePath: "/Users/miguel/cvs/vtebench/x")) else {
            print("Skipping test, we do not have the data")
            return
        }

        testFeed(
            tag: "VteBenchPerf",
            data: [UInt8](d),
            duration: Duration(secondsComponent: 10, attosecondsComponent: 0))
    }

    @Test func repeatDataFile() {
        guard let d = try? Data(contentsOf: URL(filePath: "/Users/miguel/data-file")) else {
            print("Skipping test, we do not have the data")
            return
        }

        testFeed(
            tag: "DataFilePerf",
            data: [UInt8](d),
            duration: Duration(secondsComponent: 10, attosecondsComponent: 0))
    }

    /// Release audit oracle for resize work that should scale with the
    /// materialized buffer, not the configured scrollback capacity. Configure
    /// with SWIFTTERM_PERF_SCROLLBACK, SWIFTTERM_PERF_POPULATED_LINES, and
    /// SWIFTTERM_PERF_ITERATIONS. It also proves that repeated width changes
    /// preserve visible content and cursor state.
    @Test func measureResizeAgainstScrollbackCapacity() {
        let environment = ProcessInfo.processInfo.environment
        let scrollback = Int(environment["SWIFTTERM_PERF_SCROLLBACK"] ?? "50000") ?? 50_000
        let populatedLines = Int(environment["SWIFTTERM_PERF_POPULATED_LINES"] ?? "0") ?? 0
        let iterations = max(
            1,
            Int(environment["SWIFTTERM_PERF_ITERATIONS"] ?? "30") ?? 30
        )
        let (terminal, _) = TerminalTestHarness.makeTerminal(
            cols: 80,
            rows: 24,
            scrollback: scrollback
        )

        if populatedLines > 0 {
            let row = Array("benchmark-row\r\n".utf8)
            for _ in 0..<populatedLines {
                terminal.feed(byteArray: row)
            }
        } else {
            terminal.feed(text: "top\r\nmiddle\r\nbottom")
        }

        let expectedLines = TerminalTestHarness.visibleLinesText(buffer: terminal.buffer, terminal: terminal)
        let expectedCursor = TerminalTestHarness.cursorPosition(buffer: terminal.buffer)
        let expectedCount = terminal.buffer.lines.count

        let coldStart = DispatchTime.now().uptimeNanoseconds
        terminal.resize(cols: 81, rows: 24)
        terminal.resize(cols: 80, rows: 24)
        let coldNanoseconds = DispatchTime.now().uptimeNanoseconds - coldStart

        var samples: [UInt64] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            terminal.resize(cols: 81, rows: 24)
            terminal.resize(cols: 80, rows: 24)
            samples.append(DispatchTime.now().uptimeNanoseconds - start)
        }

        samples.sort()
        let percentile: (Double) -> Double = { fraction in
            let rank = Int(ceil(fraction * Double(samples.count)))
            let index = min(samples.count - 1, max(0, rank - 1))
            return Double(samples[index]) / 1_000_000
        }
        let visibleLines = TerminalTestHarness.visibleLinesText(buffer: terminal.buffer, terminal: terminal)
        let cursor = TerminalTestHarness.cursorPosition(buffer: terminal.buffer)
        #expect(visibleLines == expectedLines)
        #expect(cursor == expectedCursor)
        #expect(terminal.buffer.lines.count == expectedCount)
        #expect(terminal.getDims().cols == 80)
        #expect(terminal.getDims().rows == 24)

        print(
            "resize-capacity scrollback=\(scrollback) populated=\(populatedLines) "
                + "materialized=\(expectedCount) iterations=\(iterations) "
                + "coldMs=\(Double(coldNanoseconds) / 1_000_000) "
                + "p50Ms=\(percentile(0.50)) p95Ms=\(percentile(0.95)) "
                + "maxMs=\(percentile(1.00))"
        )
    }

    /// Counts terminals retained after reset. A non-zero result demonstrates
    /// persistent heap growth, not timing noise, because the only strong local
    /// reference leaves scope inside each autorelease pool.
    @Test func measureResetRetention() {
        let environment = ProcessInfo.processInfo.environment
        let terminalCount = Int(environment["SWIFTTERM_PERF_TERMINALS"] ?? "100") ?? 100
        let scrollback = Int(environment["SWIFTTERM_PERF_SCROLLBACK"] ?? "50000") ?? 50_000
        var references: [WeakTerminalReference] = []
        references.reserveCapacity(terminalCount)

        for _ in 0..<terminalCount {
            autoreleasepool {
                let (terminal, _) = TerminalTestHarness.makeTerminal(
                    cols: 80,
                    rows: 24,
                    scrollback: scrollback
                )
                terminal.resetToInitialState()
                references.append(WeakTerminalReference(terminal))
            }
        }

        let retained = references.lazy.filter { $0.value != nil }.count
        print(
            "reset-retention terminals=\(terminalCount) scrollback=\(scrollback) "
                + "retained=\(retained) released=\(terminalCount - retained)"
        )
    }

}
#endif
