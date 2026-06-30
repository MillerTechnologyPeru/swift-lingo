# SwiftLingo

A Swift package that transpiles [Adobe Director](https://en.wikipedia.org/wiki/Adobe_Director) [Lingo(https://en.wikipedia.org/wiki/Lingo_(programming_language) scripts (`.ls` files) to native Swift source code, along with a runtime library for executing the generated code.

## Overview

Adobe Director used **Lingo**, a scripting language for interactive multimedia. SwiftLingo lets you bring those scripts into Swift projects by:

1. **Parsing** `.ls` Lingo source into a typed AST
2. **Transpiling** the AST to Swift classes that extend `LingoObject`
3. **Running** the generated code against a `LingoEnvironment` that bridges to your host application

## Architecture

```
SwiftLingo
├── LingoAST          – AST node types (Script, Statement, Expression, …)
├── LingoParser       – Lexer + Parser: .ls source → AST
├── LingoTranspiler   – AST → Swift source (library)
├── swiftlingoc       – CLI: swiftlingoc <input> <output-dir>
├── LingoTranspilerPlugin – SPM build-tool plugin (runs swiftlingoc at build time)
└── LingoRuntime      – LingoValue, LingoObject, LingoEnvironment
```

## How Transpilation Works

Each `.ls` file becomes a Swift class named after the file (PascalCase) that subclasses `LingoObject`:

**Input (`Button.ls`)**
```lingo
property activated

on new me
  activated = 0
  return me
end

on mouseUp me
  activated = 1
  me.doAction()
end
```

**Output (`Button.swift`)**
```swift
// Transpiled from Button.ls
import LingoRuntime

public class Button: LingoObject {
    public var `activated`: LingoValue = .void

    public override func getProperty(_ name: String) -> LingoValue { … }
    public override func setProperty(_ name: String, value: LingoValue) { … }
    public override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue { … }

    public override init() {
        super.init()
        // activated = 0
        self.`activated` = .integer(0)
    }

    public func `mouseUp`() -> LingoValue {
        // activated = 1
        self.`activated` = .integer(1)
        // me.doAction()
        _ = self.`doAction`()
        return .void
    }
}
```

Files whose names begin with `movie_` are treated as **movie scripts** and transpile to free functions (`lingo_<name>`) instead of class methods.

## Runtime

`LingoRuntime` provides the types all generated code depends on:

| Type | Role |
|---|---|
| `LingoValue` | Tagged union: `.void`, `.integer`, `.float`, `.string`, `.symbol`, `.list`, `.propertyList`, `.object`, `.boundMethod` |
| `LingoObject` | Base class for transpiled scripts; dynamic member lookup and `callMethod` dispatch |
| `LingoEnvironment` | Singleton holding global variables and global function handlers |

`LingoValue` implements the Lingo semantics you'd expect: case-insensitive string comparison, 1-based list/string indexing, chunk expressions (`char`, `word`, `item`, `line`), and arithmetic coercions.

## CLI Usage

```sh
# Transpile a single file
swiftlingoc path/to/Button.ls OutputDir/

# Transpile an entire directory of .ls files
swiftlingoc path/to/Scripts/ OutputDir/
```

Generated files are named by replacing `/` with `_` in the relative path and changing `.ls` → `.swift`, so `Actors/Button.ls` → `Actors_Button.swift`.

## SPM Build-Tool Plugin

Add `LingoTranspilerPlugin` to any target that contains `.ls` files and the transpilation runs automatically at build time:

```swift
// Package.swift
.target(
    name: "MyGame",
    plugins: [
        .plugin(name: "LingoTranspilerPlugin", package: "SwiftLingo")
    ]
)
```

## Adding SwiftLingo as a Dependency

```swift
// Package.swift
.package(url: "https://github.com/PureSwift/swift-lingo", from: "0.1.0"),
```

Available products: `LingoRuntime`, `LingoAST`, `LingoParser`, `LingoTranspiler`, `LingoTranspilerPlugin`.

## Requirements

- Swift 6.3+
- macOS / Linux

## License

See [LICENSE](LICENSE).
