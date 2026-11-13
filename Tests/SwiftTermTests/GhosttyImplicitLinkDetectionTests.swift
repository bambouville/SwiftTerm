//
//  GhosttyImplicitLinkDetectionTests.swift
//
//
//  Created by Codex on 2/26/26.
//

import Foundation
import Testing

@testable import SwiftTerm

final class GhosttyImplicitLinkDetectionTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
    }

    private func makeTerminal(for input: String) -> Terminal {
        let cols = max(256, input.count + 8)
        return Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: 1))
    }

    private func assertImplicitMatch(input: String, expected: String) {
        let terminal = makeTerminal(for: input)
        terminal.feed(text: input)

        guard let expectedRange = input.range(of: expected) else {
            Issue.record("expected match not found in input: \(expected)")
            return
        }

        let expectedStart = input.distance(from: input.startIndex, to: expectedRange.lowerBound)
        let hitOffset = expectedStart + min(1, max(expected.count - 1, 0))
        let link = terminal.link(at: .buffer(Position(col: hitOffset, row: 0)), mode: .explicitAndImplicit)
        #expect(link == expected)
    }

    private func assertNoImplicitMatch(input: String) {
        let terminal = makeTerminal(for: input)
        terminal.feed(text: input)

        let colsToCheck = max(1, input.count)
        for col in 0..<colsToCheck {
            let link = terminal.link(at: .buffer(Position(col: col, row: 0)), mode: .explicitAndImplicit)
            #expect(link == nil)
        }
    }

    @Test func testGhosttyStyleImplicitPositiveCases() {
        let cases: [(String, String)] = [
            ("hello https://example.com world", "https://example.com"),
            ("https://example.com/foo(bar) more", "https://example.com/foo(bar)"),
            ("https://example.com/foo(bar)baz more", "https://example.com/foo(bar)baz"),
            ("Link inside (https://example.com) parens", "https://example.com"),
            ("Link period https://example.com. More text.", "https://example.com"),
            ("Link trailing comma https://example.com, more text.", "https://example.com"),
            ("Link in double quotes \"https://example.com\" and more", "https://example.com"),
            ("Link in single quotes 'https://example.com' and more", "https://example.com"),
            ("some file with https://google.com https://duckduckgo.com links.", "https://google.com"),
            ("and links in it. links https://yahoo.com mailto:test@example.com ssh://1.2.3.4", "https://yahoo.com"),
            ("also match http://example.com non-secure links", "http://example.com"),
            ("match tel://+12123456789 phone numbers", "tel://+12123456789"),
            ("match tel:+18005551234 tel links", "tel:+18005551234"),
            ("match with query url https://example.com?query=1&other=2 and more text.", "https://example.com?query=1&other=2"),
            ("url with dashes [mode 2027](https://github.com/contour-terminal/terminal-unicode-core) for better unicode support", "https://github.com/contour-terminal/terminal-unicode-core"),
            ("dot.http://example.com", "http://example.com"),
            ("weird characters https://example.com/~user/?query=1&other=2#hash and more", "https://example.com/~user/?query=1&other=2#hash"),
            ("square brackets https://example.com/[foo] and more", "https://example.com/[foo]"),
            ("[13]:TooManyStatements: TempFile#assign_temp_file_to_entity has approx 7 statements [https://example.com/docs/Too-Many-Statements.md]", "https://example.com/docs/Too-Many-Statements.md"),
            ("match ftp://example.com ftp links", "ftp://example.com"),
            ("match file://example.com file links", "file://example.com"),
            ("match ssh://example.com ssh links", "ssh://example.com"),
            ("match git://example.com git links", "git://example.com"),
            ("/tmp/test.txt http://www.google.com", "/tmp/test.txt"),
            ("match news:comp.infosystems.www.servers.unix news links", "news:comp.infosystems.www.servers.unix"),
            ("Serving HTTP on :: port 8000 (http://[::]:8000/)", "http://[::]:8000/"),
            ("IPv6 address https://[2001:db8::1]:8080/path", "https://[2001:db8::1]:8080/path"),
            ("../example.py", "../example.py"),
            ("../example.py ", "../example.py "),
            ("first time ../example.py contributor ", "../example.py"),
            ("src/config/url.zig", "src/config/url.zig"),
            ("app/folder/file.rb:1", "app/folder/file.rb:1"),
            ("lib/ghostty/terminal.zig:42:10", "lib/ghostty/terminal.zig:42:10"),
            ("~/foo/bar.txt", "~/foo/bar.txt"),
            ("$HOME/src/config/url.zig", "$HOME/src/config/url.zig"),
            ("foo/$BAR/baz", "foo/$BAR/baz"),
            (".foo/bar/$VAR", ".foo/bar/$VAR"),
            (".config/ghostty/config", ".config/ghostty/config"),
            ("loaded from .local/share/ghostty/state.db now", ".local/share/ghostty/state.db"),
            ("  - shared/src/foo/SomeItem.m:12, shared/src/", "shared/src/foo/SomeItem.m:12"),
            ("foo.local/share", "foo.local/share"),
            ("2024/report.txt", "2024/report.txt"),
            ("./spaces-end.   ", "./spaces-end.   "),
            ("./space middle", "./space middle")
        ]

        for (input, expected) in cases {
            assertImplicitMatch(input: input, expected: expected)
        }
    }

    @Test func testGhosttyStyleImplicitNoMatchCases() {
        let noMatchCases = [
            "example.com",
            "www.example.com",
            "input/output",
            "foo/bar",
            "$10/bar",
            "$10/$20",
            "$10/bar.txt",
            "foo/bar,baz.txt",
            "foo$BAR/baz.txt",
            "foo~/bar.txt",
            "// foo bar",
            "//foo"
        ]

        for input in noMatchCases {
            assertNoImplicitMatch(input: input)
        }
    }

    @Test func testGhosttyStyleImplicitSpansWrappedRows() {
        let input = "https://example.com/this/is/a/wrapped/link"
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 10, rows: 8))
        terminal.feed(text: input)

        let row0 = terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit)
        #expect(row0 == input)

        let row1 = terminal.link(at: .buffer(Position(col: 2, row: 1)), mode: .explicitAndImplicit)
        #expect(row1 == input)

        let row2 = terminal.link(at: .buffer(Position(col: 2, row: 2)), mode: .explicitAndImplicit)
        #expect(row2 == input)
    }

    /// Feeds `text` from the origin of an 80-column screen and looks up the
    /// cell holding the first character of `probe`.
    private func wrappedLink(in text: String, at probe: String, offset: Int = 1, columns cols: Int = 80) -> String? {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: text.count / cols + 2, scrollback: 0))
        terminal.feed(text: text)
        guard let range = text.range(of: probe) else {
            Issue.record("probe not found: \(probe)")
            return nil
        }
        let index = text.distance(from: text.startIndex, to: range.lowerBound) + offset
        return terminal.link(at: .buffer(Position(col: index % cols, row: index / cols)), mode: .explicitAndImplicit)
    }

    // Terminal output is hostile input. Before the URL pattern was made
    // linear the first rows here never returned: each added period tripled
    // the time.
    @Test func testHostileRowsAnswerQuickly() {
        let hostile: [(String, String)] = [
            ("periods", "https://" + String(repeating: ".", count: 200)),
            ("periods and commas", "https://" + String(repeating: ",.", count: 100)),
            ("unterminated ipv6", "https://[" + String(repeating: ":", count: 200)),
            ("ipv6 hex", "http://[" + String(repeating: "a:", count: 100) + " x"),
            ("bracketed words", "https://a" + String(repeating: "(b)", count: 60) + "."),
            ("segments", String(repeating: "a/", count: 2000) + " x"),
            ("run without a dot", String(repeating: "abcdefgh/", count: 450)),
            ("separators", String(repeating: ";/", count: 2000)),
            ("schemes", String(repeating: "https://.", count: 400)),
        ]
        for (name, input) in hostile {
            let terminal = makeTerminal(for: input)
            terminal.feed(text: input)
            let started = Date()
            for col in stride(from: 0, to: input.count, by: max(8, input.count / 40)) {
                _ = terminal.link(at: .buffer(Position(col: col, row: 0)), mode: .explicitAndImplicit)
            }
            #expect(Date().timeIntervalSince(started) < 2, "\(name)")
        }
    }

    // A line with no newline can be megabytes long. Only the rows near the
    // lookup are joined, and the path patterns see less still.
    @Test func testAVeryLongWrappedLineIsBounded() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 80, rows: 24, scrollback: 8000))
        terminal.feed(text: String(repeating: "abcdefgh/", count: 44_000))
        let row = terminal.buffer.lines.count / 2
        let started = Date()
        for col in stride(from: 0, to: 80, by: 4) {
            #expect(terminal.link(at: .buffer(Position(col: col, row: row)), mode: .explicitAndImplicit) == nil)
        }
        #expect(Date().timeIntervalSince(started) < 2)
    }

    // A link that runs off the joined rows is refused: opening its first
    // part would open a different address.
    @Test func testALinkLongerThanTheWindowIsRefusedNotTruncated() {
        let cols = 80
        let budget = Terminal.implicitLinkRowBudget(cols: cols)
        let fits = "https://example.com/" + String(repeating: "a", count: cols * (budget - 2))
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: budget * 4, scrollback: 0))
        terminal.feed(text: fits)
        #expect(terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit) == fits)
        #expect(terminal.link(at: .buffer(Position(col: 2, row: (fits.count - 1) / cols)), mode: .explicitAndImplicit) == fits)

        let long = "https://example.com/" + String(repeating: "a", count: cols * (budget * 3))
        let other = Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: budget * 4, scrollback: 0))
        other.feed(text: long)
        // From its first row the end is out of reach; from its last, the start.
        #expect(other.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit) == nil)
        let lastRow = (long.count - 1) / cols
        #expect(other.link(at: .buffer(Position(col: 2, row: lastRow)), mode: .explicitAndImplicit) == nil)
    }

    // The tail of a URL whose start is out of reach is not a path, and a URL
    // glued to the end of one is not a URL of its own.
    @Test func testTheTailOfAnOutOfReachURLIsNotALink() {
        let query = "https://example.com/?q=" + String(repeating: "=", count: 6000)
        #expect(wrappedLink(in: query + "dir/file.txt END", at: "file.txt") == nil)
        #expect(wrappedLink(in: query + "https://other.example/x END", at: "other.example") == nil)
        // Where the long URL ends for certain, what follows stands alone.
        #expect(wrappedLink(in: query + "\"dir/file.txt\" END", at: "file.txt") == "dir/file.txt")
        #expect(wrappedLink(in: query + "  dir/file.txt END", at: "file.txt") == "dir/file.txt")
        #expect(wrappedLink(in: query + " https://other.example/x END", at: "other.example") == "https://other.example/x")
    }

    // Long lines of ordinary output keep their links.
    @Test func testLinksDeepInALongLineAreStillFound() {
        let prose = String(repeating: "lorem ipsum dolor sit amet ", count: 120)
        #expect(wrappedLink(in: prose + "see src/main/app.swift for it " + prose, at: "src/main") == "src/main/app.swift")
        #expect(wrappedLink(in: prose + "see https://example.com/a?b=c, then " + prose, at: "example.com") == "https://example.com/a?b=c")
        // No whitespace anywhere, as in minified JSON.
        let filler = String(repeating: "{\"k\":\"vvvvvvvv\"},", count: 300)
        #expect(wrappedLink(in: filler + "{\"path\":\"src/main/app.swift\"}," + filler, at: "src/main") == "src/main/app.swift")
        #expect(wrappedLink(in: filler + "{\"url\":\"https://example.com/a\"}," + filler, at: "example.com") == "https://example.com/a")
    }

    // What a caller with its own link rules is given to look in.
    @Test func testLinkLineContextJoinsWrappedRowsAroundTheLocation() {
        let cols = 20
        let text = "see https://example.com/abcdefghijklmnop now"
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: 6, scrollback: 0))
        terminal.feed(text: text + "\r\nnext line")
        let index = text.distance(from: text.startIndex, to: text.range(of: "ghij")!.lowerBound)
        let context = terminal.linkLineContext(at: .buffer(Position(col: index % cols, row: index / cols)))
        #expect(context?.text == text)
        #expect(context?.offset == index)
        #expect(context?.truncatedStart == false)
        #expect(context?.truncatedEnd == false)
        #expect(terminal.linkLineContext(at: .buffer(Position(col: 15, row: 3)))?.text == nil)

        let long = Terminal(delegate: self, options: TerminalOptions(cols: 80, rows: 24, scrollback: 400))
        long.feed(text: String(repeating: "abcdefgh ", count: 2000))
        let middle = long.linkLineContext(at: .buffer(Position(col: 4, row: long.buffer.lines.count / 2)))
        #expect(middle?.truncatedStart == true)
        #expect(middle?.truncatedEnd == true)
        #expect((middle?.text.count ?? 0) <= 2 * Terminal.implicitLinkWindowCharacters + 80)
    }

    // A URL that ends at the right edge stops there: the space that opens
    // the next row belongs to the text, not to indentation.
    @Test func testASpaceThatOpensAWrappedRowEndsTheLink() {
        #expect(wrappedLink(in: "see https://example.com/abcdefghijklmnop now", at: "example", columns: 20)
            == "https://example.com/abcdefghijklmnop")
        #expect(wrappedLink(in: "see https://example.com/abcdefghijklmnop now", at: "ghij", columns: 20)
            == "https://example.com/abcdefghijklmnop")
    }

    // A URL is looked for first, so a path can no longer swallow one.
    @Test func testAURLWinsOverAPathThatContainsIt() {
        assertImplicitMatch(input: "see ./mirror/https://example.com/a.txt now", expected: "https://example.com/a.txt")
        assertImplicitMatch(input: "see ./mirror/https://example.com/a.txt now", expected: "./mirror/")
    }

    // The linear pattern accepts what the nested one did.
    @Test func testBracketedWordsAndIPv6HostsStillMatch() {
        let cases: [(String, String)] = [
            ("see https://example.com/a(b)(c) now", "https://example.com/a(b)"),
            ("see https://example.com/a[b]c[d] now", "https://example.com/a[b]c[d]"),
            ("see http://[::1]:8080/path now", "http://[::1]:8080/path"),
            ("see http://[fe80::1]/x, then", "http://[fe80::1]/x"),
        ]
        for (input, expected) in cases {
            assertImplicitMatch(input: input, expected: expected)
        }
        // A bracketed word cannot open a URL.
        assertNoImplicitMatch(input: "x https://(nope)")
    }
}
