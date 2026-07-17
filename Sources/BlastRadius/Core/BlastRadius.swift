//
//  BlastRadius.swift
//  SwiftBlastRadius
//
//  "What's the ripple of this change?" — for each symbol touched by a diff, find
//  its callers and covering tests across a project. Deterministic whole-word
//  search (same spirit as Find Usages). The human does the reasoning.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Finds the project-wide impact of the symbols touched by a change.
///
/// The symbol-resolution step (mapping changed lines to their enclosing symbol
/// names) is injected via a closure, so this stays language- and parser-agnostic —
/// wire it to tree-sitter breadcrumbs, ctags, an LSP, or anything else.
public enum BlastRadius {

    /// The built-in noise list skipped while walking the project.
    public static let defaultSkip: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", ".swiftpm", "Pods",
        "DerivedData", "dist", "build", "__pycache__", ".next", ".cache", "vendor",
    ]

    /// Directory names skipped while walking the project. Defaults to
    /// ``defaultSkip``; assign to override (e.g. from a user preference — a
    /// project with real sources in `dist/` needs it off the list).
    ///
    /// - Important: Global mutable state read by every ``analyze(file:root:changedLines:enclosingSymbol:)``
    ///   walk. Set it during start-up, not concurrently with an analysis.
    public static var skip: Set<String> = defaultSkip

    /// Source file extensions searched for usages.
    public static let exts: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "py", "rb", "php", "go", "rs",
        "java", "c", "cpp", "cc", "h", "hpp", "cs", "kt", "dart", "lua", "scala",
    ]

    /// Analyzes the impact of the changed lines in `file`.
    ///
    /// - Parameters:
    ///   - file: The changed file.
    ///   - root: The project root to search.
    ///   - changedLines: 1-based line numbers that changed in `file`.
    ///   - enclosingSymbol: Given a character offset into the file text and that
    ///     text, returns the breadcrumb trail of enclosing symbols; the **last**
    ///     element is the innermost symbol. (Wire this to your symbol source.)
    /// - Returns: One ``SymbolImpact`` per changed symbol that has any usages.
    /// - Note: Blocking — reads `file` and walks/reads the whole project tree
    ///   synchronously. Call off the main thread.
    public static func analyze(file: URL, root: URL, changedLines: Set<Int>,
                               enclosingSymbol: (_ charOffset: Int, _ text: String) -> [String]) -> [SymbolImpact] {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let symbols = changedSymbols(content: content, changedLines: changedLines, enclosingSymbol: enclosingSymbol)
        guard !symbols.isEmpty else { return [] }
        let files = sourceFiles(root)
        return symbols.compactMap { name -> SymbolImpact? in
            let (callers, tests) = usages(of: name, in: files, root: root)
            guard !callers.isEmpty || !tests.isEmpty else { return nil }
            return SymbolImpact(symbol: name, callers: callers, tests: tests)
        }
    }

    /// Project-wide references to a single named symbol — the "Find References"
    /// entry point (``analyze(file:root:changedLines:enclosingSymbol:)`` is the
    /// diff-driven one). Same deterministic whole-word search, so it is honest
    /// about being NAME-based, not semantic: it finds every whole-word `name`
    /// (a same-named field, a mention in a string) and can't tell two same-named
    /// methods on different types apart. That's the right tradeoff for a
    /// language-agnostic review tool with no language server — but callers should
    /// present it as "References", not a compiler-accurate call hierarchy.
    ///
    /// - Returns: A ``SymbolImpact`` (callers + covering tests), or nil when the
    ///   symbol has no whole-word hits anywhere in the project.
    /// - Note: Blocking — walks and reads the project tree synchronously. Call
    ///   off the main thread.
    public static func references(to name: String, root: URL) -> SymbolImpact? {
        guard name.count > 1 else { return nil }
        let (callers, tests) = usages(of: name, in: sourceFiles(root), root: root)
        guard !callers.isEmpty || !tests.isEmpty else { return nil }
        return SymbolImpact(symbol: name, callers: callers, tests: tests)
    }

    /// Distinct innermost enclosing symbols of the changed lines.
    private static func changedSymbols(content: String, changedLines: Set<Int>,
                                       enclosingSymbol: (Int, String) -> [String]) -> [String] {
        let ns = content as NSString
        var seen: [String] = []
        for line in changedLines.sorted() {
            let crumbs = enclosingSymbol(charOffset(line, ns), content)
            if let name = crumbs.last, name.count > 1, !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    /// Converts a 1-based git line number to a UTF-16 offset. Counts lines the way
    /// git does — by `\n` only — never by Unicode separators (U+2028/U+2029/U+0085),
    /// which `NSString.lineRange` treats as breaks and would skew the offset.
    private static func charOffset(_ line: Int, _ ns: NSString) -> Int {
        var cur = 1, idx = 0
        while cur < line, idx < ns.length {
            if ns.character(at: idx) == 0x0A { cur += 1 }
            idx += 1
        }
        return min(idx, ns.length)
    }

    /// Whole-word searches `files` for `name`, splitting hits into (callers, tests).
    /// Skips files ≥ 500 KB and stops past 300 total hits.
    private static func usages(of name: String, in files: [URL], root: URL) -> ([BlastLocation], [BlastLocation]) {
        // `\b` next to a non-word character inverts its meaning (\b==\b never matches
        // ` a == b `), so only anchor the ends of the name that are word characters —
        // fully non-word names (operators like `==`) fall back to a literal search.
        func isWordChar(_ c: Character?) -> Bool {
            guard let c else { return false }
            return c == "_" || c.isLetter || c.isNumber
        }
        let pattern = (isWordChar(name.first) ? "\\b" : "")
            + NSRegularExpression.escapedPattern(for: name)
            + (isWordChar(name.last) ? "\\b" : "")
        guard let re = try? NSRegularExpression(pattern: pattern) else { return ([], []) }
        var callers: [BlastLocation] = [], tests: [BlastLocation] = []
        for f in files {
            guard let content = try? String(contentsOf: f, encoding: .utf8), content.utf8.count < 500_000 else { continue }
            let isTest = isTestFile(f, root: root)
            for (i, line) in content.components(separatedBy: "\n").enumerated() {
                let r = NSRange(location: 0, length: (line as NSString).length)
                guard re.firstMatch(in: line, range: r) != nil else { continue }
                let loc = BlastLocation(file: rel(f, root), line: i + 1, text: line.trimmingCharacters(in: .whitespaces), absPath: f.path, isTest: isTest)
                if isTest { tests.append(loc) } else { callers.append(loc) }
                if callers.count + tests.count > 300 { return (callers, tests) }
            }
        }
        return (callers, tests)
    }

    /// Classifies from the root-relative path only (so the checkout location can't
    /// flip it) and matches whole path components / filename word boundaries — never
    /// raw substrings, which would hit "latest", "InspectorPanel", "PerspectiveView"…
    private static func isTestFile(_ f: URL, root: URL) -> Bool {
        let words = ["test", "tests", "spec", "specs"]
        let dirNames: Set<String> = ["test", "tests", "__tests__", "spec", "specs", "testing"]
        let parts = rel(f, root).split(separator: "/")
        for dir in parts.dropLast() where dirNames.contains(dir.lowercased()) { return true }
        let stem = f.deletingPathExtension().lastPathComponent
        // CamelCase suffixes (MyTests, FooSpec) — capitalized, so "latest" can't match.
        if ["Test", "Tests", "Spec", "Specs"].contains(where: { stem.hasSuffix($0) }) { return true }
        let lower = stem.lowercased()
        for word in words {
            if lower == word { return true }
            for sep in [".", "_", "-"] where lower.hasSuffix(sep + word) || lower.hasPrefix(word + sep) { return true }
        }
        return false
    }

    /// Walks `root` for source files (by ``exts``), pruning ``skip`` directories
    /// and capping the walk at 6000 files.
    private static func sourceFiles(_ root: URL) -> [URL] {
        var out: [URL] = []
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        for case let url as URL in en {
            if skip.contains(url.lastPathComponent) { en.skipDescendants(); continue }
            if exts.contains(url.pathExtension.lowercased()) { out.append(url) }
            if out.count > 6000 { break }
        }
        return out
    }

    /// Root-relative path of `url`, or just its filename if it's outside `root`.
    private static func rel(_ url: URL, _ root: URL) -> String {
        // Resolve symlinks on both sides — the enumerator can yield /private/var/…
        // for a /var/… root, which would otherwise defeat the prefix check.
        let u = url.resolvingSymlinksInPath().path, r = root.resolvingSymlinksInPath().path
        return u.hasPrefix(r) ? String(u.dropFirst(r.count).drop(while: { $0 == "/" })) : url.lastPathComponent
    }
}
