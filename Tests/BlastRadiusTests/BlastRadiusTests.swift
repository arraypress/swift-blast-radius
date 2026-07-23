//
//  BlastRadiusTests.swift
//  Tests for SwiftBlastRadius
//
//  Created by David Sherlock on 7/9/26.
//

import XCTest
@testable import BlastRadius

final class BlastRadiusTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDownWithError() throws {
        for d in scratch { try? FileManager.default.removeItem(at: d) }
        scratch.removeAll()
    }

    /// A temp project: `changed.swift` defines+calls `foo`, `caller.swift` calls it,
    /// `MyTests.swift` calls it, and `node_modules/pkg.js` also calls it (must be skipped).
    private func makeProject() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blast-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scratch.append(root)
        func write(_ rel: String, _ body: String) throws {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("changed.swift", "func foo() {\n    return\n}\nfoo()\n")
        try write("caller.swift", "func bar() {\n    foo()\n}\n")
        try write("MyTests.swift", "func testFoo() {\n    foo()\n}\n")
        try write("node_modules/pkg.js", "foo();\n")   // must be skipped
        try write("unrelated.swift", "func baz() {}\n")
        return root
    }

    func testFindsCallersAndTestsForChangedSymbol() throws {
        let root = try makeProject()
        let changed = root.appendingPathComponent("changed.swift")
        // Inject a breadcrumb resolver that reports the changed line is inside `foo`.
        let impacts = BlastRadius.analyze(file: changed, root: root, changedLines: [2]) { _, _ in ["foo"] }

        XCTAssertEqual(impacts.count, 1)
        let impact = try XCTUnwrap(impacts.first)
        XCTAssertEqual(impact.symbol, "foo")
        // callers: changed.swift (def + call) + caller.swift — never node_modules
        XCTAssertTrue(impact.callers.contains { $0.file == "caller.swift" })
        XCTAssertFalse(impact.callers.contains { $0.file.contains("node_modules") })
        XCTAssertFalse(impact.tests.contains { $0.file.contains("node_modules") })
        // tests: MyTests.swift
        XCTAssertTrue(impact.tests.contains { $0.file == "MyTests.swift" })
        XCTAssertTrue(impact.tests.allSatisfy { $0.isTest })
        XCTAssertTrue(impact.callers.allSatisfy { !$0.isTest })
    }

    func testNoChangedSymbolsYieldsNothing() throws {
        let root = try makeProject()
        let changed = root.appendingPathComponent("changed.swift")
        // Resolver returns no breadcrumbs → no symbols → no impacts.
        let impacts = BlastRadius.analyze(file: changed, root: root, changedLines: [2]) { _, _ in [] }
        XCTAssertTrue(impacts.isEmpty)
    }

    func testSymbolWithNoUsagesIsFilteredOut() throws {
        let root = try makeProject()
        let changed = root.appendingPathComponent("changed.swift")
        // `nonexistentSymbol` appears nowhere → filtered out.
        let impacts = BlastRadius.analyze(file: changed, root: root, changedLines: [2]) { _, _ in ["nonexistentSymbol"] }
        XCTAssertTrue(impacts.isEmpty)
    }

    func testWholeWordMatchingOnly() throws {
        let root = try makeProject()
        // "oo" should NOT match inside "foo".
        let changed = root.appendingPathComponent("changed.swift")
        let impacts = BlastRadius.analyze(file: changed, root: root, changedLines: [2]) { _, _ in ["oo"] }
        XCTAssertTrue(impacts.isEmpty)
    }

    func testUsesLastBreadcrumbAsInnermostSymbol() throws {
        let root = try makeProject()
        let changed = root.appendingPathComponent("changed.swift")
        // trail [Outer, foo] → innermost is foo.
        let impacts = BlastRadius.analyze(file: changed, root: root, changedLines: [2]) { _, _ in ["Outer", "foo"] }
        XCTAssertEqual(impacts.first?.symbol, "foo")
    }

    // MARK: - Regressions

    /// Regression: test-file classification must not substring-match "test"/"spec"
    /// inside unrelated words ("InspectorPanel", "PerspectiveView") or in path
    /// components above the project root (a checkout under ~/latest/…).
    func testTestFileClassificationIgnoresSubstringsAndCheckoutPath() throws {
        // Root path deliberately contains "test" and "spec" as substrings.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("latest-contest-perspective-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scratch.append(root)
        func write(_ rel: String, _ body: String) throws {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("changed.swift", "func foo() {\n    return\n}\n")
        try write("InspectorPanel.swift", "foo()\n")       // "spec" substring — NOT a test
        try write("PerspectiveView.swift", "foo()\n")      // "spec" substring — NOT a test
        try write("caller.swift", "foo()\n")
        try write("MyTests.swift", "foo()\n")              // *Tests.swift — a test
        try write("tests/helpers.swift", "foo()\n")        // tests/ dir — a test
        try write("test_foo.py", "foo()\n")                // pytest naming — a test

        let changed = root.appendingPathComponent("changed.swift")
        let impacts = BlastRadius.analyze(file: changed, root: root, changedLines: [2]) { _, _ in ["foo"] }
        let impact = try XCTUnwrap(impacts.first)
        for file in ["InspectorPanel.swift", "PerspectiveView.swift", "caller.swift"] {
            XCTAssertTrue(impact.callers.contains { $0.file == file }, "\(file) should be a caller")
            XCTAssertFalse(impact.tests.contains { $0.file == file }, "\(file) must not be a test")
        }
        for file in ["MyTests.swift", "tests/helpers.swift", "test_foo.py"] {
            XCTAssertTrue(impact.tests.contains { $0.file == file }, "\(file) should be a test")
        }
    }

    /// Regression: a fully non-word symbol (an operator like `==`) must still find
    /// idiomatic spaced call sites — `\b==\b` never matches ` a == b `.
    func testOperatorSymbolFindsSpacedUsages() throws {
        let root = try makeProject()
        let url = root.appendingPathComponent("ops.swift")
        try "func check(a: Int, b: Int) -> Bool {\n    return a == b\n}\n".write(to: url, atomically: true, encoding: .utf8)
        let impacts = BlastRadius.analyze(file: url, root: root, changedLines: [2]) { _, _ in ["=="] }
        let impact = try XCTUnwrap(impacts.first)
        XCTAssertEqual(impact.symbol, "==")
        XCTAssertTrue(impact.callers.contains { $0.file == "ops.swift" && $0.line == 2 })
    }

    /// Regression: changed line numbers are git line numbers (`\n`-counted), so a
    /// mid-line U+2028 must not shift the offset handed to the symbol resolver.
    func testCharOffsetCountsNewlinesOnlyNotUnicodeSeparators() throws {
        let root = try makeProject()
        let url = root.appendingPathComponent("sep.js")
        let content = "line1\u{2028}still\nline2\nfoo()\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
        var captured: Int?
        _ = BlastRadius.analyze(file: url, root: root, changedLines: [3]) { offset, _ in
            captured = offset
            return ["foo"]
        }
        let offset = try XCTUnwrap(captured)
        XCTAssertTrue((content as NSString).substring(from: offset).hasPrefix("foo()"),
                      "git line 3 should resolve to the start of the third \\n-line, got offset \(offset)")
    }

    /// Regression: the batch analyze (one tree walk + one read pass for the whole
    /// changeset) must produce exactly what per-file calls do — including a line
    /// that mentions SEVERAL changed symbols, which must bucket under each of them.
    func testBatchAnalyzeMatchesPerFileCallsAndBucketsSharedLines() throws {
        let root = try makeProject()
        func write(_ rel: String, _ body: String) throws {
            try body.write(to: root.appendingPathComponent(rel), atomically: true, encoding: .utf8)
        }
        try write("defsA.swift", "func alpha() {}\n")
        try write("defsB.swift", "func beta() {}\n")
        try write("both.swift", "alpha(); beta()\n")
        let resolver: (Int, String) -> [String] = { _, text in
            if text.contains("func alpha") { return ["alpha"] }
            if text.contains("func beta") { return ["beta"] }
            return []
        }
        let a = root.appendingPathComponent("defsA.swift")
        let b = root.appendingPathComponent("defsB.swift")

        let batch = BlastRadius.analyze(files: [(a, [1]), (b, [1])], root: root, enclosingSymbol: resolver)
        for file in [a, b] {
            XCTAssertEqual(batch[file],
                           BlastRadius.analyze(file: file, root: root, changedLines: [1], enclosingSymbol: resolver),
                           file.lastPathComponent)
        }
        // The line mentioning both symbols must appear under BOTH, not just one.
        XCTAssertTrue(batch[a]?.first?.callers.contains { $0.file == "both.swift" && $0.line == 1 } ?? false)
        XCTAssertTrue(batch[b]?.first?.callers.contains { $0.file == "both.swift" && $0.line == 1 } ?? false)
    }

    /// Regression: operator symbols keep their literal (un-anchored) matching in
    /// the batched single-pass search alongside word symbols.
    func testBatchAnalyzeKeepsOperatorMatching() throws {
        let root = try makeProject()
        let ops = root.appendingPathComponent("ops.swift")
        try "func check(a: Int, b: Int) -> Bool {\n    return a == b\n}\n".write(to: ops, atomically: true, encoding: .utf8)
        let changed = root.appendingPathComponent("changed.swift")
        let resolver: (Int, String) -> [String] = { _, text in
            text.contains("func check") ? ["=="] : ["foo"]
        }
        let batch = BlastRadius.analyze(files: [(changed, [2]), (ops, [2])], root: root, enclosingSymbol: resolver)
        XCTAssertEqual(batch[changed]?.first?.symbol, "foo")
        let opImpact = try XCTUnwrap(batch[ops]?.first)
        XCTAssertEqual(opImpact.symbol, "==")
        XCTAssertTrue(opImpact.callers.contains { $0.file == "ops.swift" && $0.line == 2 })
    }

    // MARK: - references(to:root:)

    func testReferencesFindsCallersAndTestsByName() throws {
        let root = try makeProject()
        let impact = try XCTUnwrap(BlastRadius.references(to: "foo", root: root))
        XCTAssertEqual(impact.symbol, "foo")
        // Every non-test whole-word hit is a caller; node_modules is skipped.
        XCTAssertTrue(impact.callers.contains { $0.file == "caller.swift" })
        XCTAssertTrue(impact.callers.allSatisfy { $0.file != "node_modules/pkg.js" })
        XCTAssertTrue(impact.tests.contains { $0.file == "MyTests.swift" })
    }

    func testReferencesToUnknownSymbolIsNil() throws {
        let root = try makeProject()
        XCTAssertNil(BlastRadius.references(to: "nonexistent", root: root))
    }

    func testReferencesRejectsOneCharacterNames() throws {
        let root = try makeProject()
        // count > 1 guard: a single char would match far too much to be useful.
        XCTAssertNil(BlastRadius.references(to: "x", root: root))
    }
}
