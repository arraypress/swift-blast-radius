# Swift Blast Radius

*"What's the ripple of this change?"* — for each symbol touched by a diff, find its **callers** and **covering tests** across a project. A fast, deterministic, language-agnostic change-impact tool in the spirit of Find Usages — it surfaces where to look; the human does the reasoning. Pure Foundation, zero dependencies.

## Features

- 💥 **Change impact** — `BlastRadius.analyze(file:root:changedLines:enclosingSymbol:)` maps changed lines → their enclosing symbols → one `SymbolImpact` per symbol with any project-wide usages
- 🧪 **Callers vs. tests** — every hit is a `BlastLocation` (file, line, trimmed text) split into `callers` and `tests`, so you see coverage at a glance; test files are classified by whole path components and filename word boundaries (never raw substrings, so "latest" and "InspectorPanel" can't misfire)
- 🔌 **Parser-agnostic** — the "which symbol encloses this offset" step is the injected `enclosingSymbol` closure; wire it to tree-sitter breadcrumbs, ctags, an LSP, or anything else
- 🧭 **Whole-word matching** — word-boundary anchored search, so `oo` never matches inside `foo`; fully non-word names (operators like `==`) fall back to a literal search
- 🚫 **Noise-aware** — prunes `BlastRadius.skip` directories (`node_modules`, `.build`, `Pods`, `__pycache__`, …), searches only `BlastRadius.exts` source extensions, and caps work (6000 files, 500 KB per file, 300 hits per symbol) for responsiveness
- 🪶 **Zero dependencies** — Foundation only
- 🧪 **Fully tested** — unit tests against throwaway on-disk projects, including test-file classification, operator symbols, and Unicode line-separator edge cases

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-blast-radius.git", from: "1.0.0")
]
```

## Usage

```swift
import BlastRadius

// Analyze the impact of lines 20–22 changing in a file.
// The closure is your symbol source: given a UTF-16 character offset and the
// file text, return the enclosing-symbol breadcrumb trail (innermost last).
let impacts = BlastRadius.analyze(
    file: changedFileURL,
    root: projectRoot,
    changedLines: [20, 21, 22]
) { charOffset, text in
    mySymbolProvider.breadcrumbs(at: charOffset, in: text)
}

// One SymbolImpact per changed symbol that has any usages.
for impact in impacts {
    print("\(impact.symbol): \(impact.callers.count) callers, \(impact.tests.count) tests")
    for loc in impact.callers {
        print("  \(loc.file):\(loc.line)  \(loc.text)")   // loc.absPath opens the file
    }
}
```

> ⚠️ It's a deterministic **text search**, not a semantic call graph — it can match a same-named symbol in an unrelated file and doesn't follow imports/scoping. That's the trade for being fast and language-agnostic. `analyze` walks and reads the whole project synchronously — run it off the main thread.

## License

MIT
