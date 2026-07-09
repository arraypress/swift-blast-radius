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
}
