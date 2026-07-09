# Swift Blast Radius

*"What's the ripple of this change?"* — for each symbol touched by a diff, find its **callers** and **covering tests** across a project. A fast, deterministic, language-agnostic change-impact tool in the spirit of Find Usages. It surfaces where to look; the human does the reasoning.

## Features

- 💥 **Change impact** — map changed lines → their enclosing symbols → every usage across the project
- 🧪 **Callers vs. tests** — usages are split by whether they live in a test file, so you see coverage at a glance
- 🔌 **Parser-agnostic** — the "which symbol encloses this line" step is an injected closure; wire it to tree-sitter, ctags, an LSP, or anything
- 🧭 **Whole-word matching** — `\bname\b`, so `oo` never matches inside `foo`
- 🚫 **Noise-aware** — skips `node_modules`, `.build`, `Pods`, `__pycache__`, … and caps work for responsiveness
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-blast-radius.git", from: "1.0.0")
]
```

## Usage

```swift
import BlastRadius

let impacts = BlastRadius.analyze(
    file: changedFileURL,
    root: projectRoot,
    changedLines: [20, 21, 22]
) { charOffset, text in
    // Your symbol source: return the enclosing-symbol breadcrumb trail.
    mySymbolProvider.breadcrumbs(at: charOffset, in: text)
}

for impact in impacts {
    print("\(impact.symbol): \(impact.callers.count) callers, \(impact.tests.count) tests")
}
```

> ⚠️ It's a deterministic **text search**, not a semantic call graph — it can match a same-named symbol in an unrelated file and doesn't follow imports/scoping. That's the trade for being fast and language-agnostic. Run it off the main thread.

## License

MIT
