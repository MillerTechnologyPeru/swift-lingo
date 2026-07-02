# SwiftLingo

A Swift package for working with [Adobe Director](https://en.wikipedia.org/wiki/Adobe_Director) [Lingo](https://en.wikipedia.org/wiki/Lingo_(programming_language)) from Swift. It can parse `.ls` source, transpile it to native Swift, parse and decompile compiled Director bytecode, and execute bytecode directly through a small VM and host harness.

## Overview

Adobe Director used **Lingo**, a scripting language for interactive multimedia. SwiftLingo lets you bring those scripts into Swift projects by:

1. **Parsing** `.ls` Lingo source into a typed AST
2. **Transpiling** the AST to Swift classes that extend `LingoObject`
3. **Parsing and decompiling** compiled Director Lingo bytecode into the same AST shape
4. **Running** generated Swift or bytecode against an explicit `LingoEnvironment` and host-provided objects

## Architecture

```
SwiftLingo
├── LingoAST              – AST node types (Script, Statement, Expression, …)
├── LingoParser           – Lexer + Parser: .ls source → AST
├── LingoTranspiler       – AST → Swift source (library)
├── swiftlingoc           – CLI: swiftlingoc <input> <output-dir>
├── LingoTranspilerPlugin – SPM build-tool plugin (runs swiftlingoc at build time)
├── LingoBytecode         – Director script chunks, opcodes, literals, and decompiler
├── LingoRuntime          – LingoValue, LingoObject, LingoEnvironment
└── LingoVM               – Bytecode interpreter, host protocol, and harness helpers
```

## How Transpilation Works

Each `.ls` file becomes a Swift class named after the file (PascalCase) that subclasses `LingoObject`. Handlers map to Swift functions, with default parameters to match Lingo's optional arguments, and properties are correctly hoisted and managed dynamically.

**Input (`Button.ls`)**
```lingo
property activated

on new me, startingState
  if voidP(startingState) then
    activated = 0
  else
    activated = startingState
  end if
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

    public override func getProperty(_ name: String) -> LingoValue { ... }
    public override func setProperty(_ name: String, value: LingoValue) { ... }
    
    private enum MethodName: String {
        case `mouseup` = "mouseup"
    }

    public override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue { ... }

    public init(_ `startingstate`: LingoValue = LingoValue.void) {
        super.init()
        var `startingstate`: LingoValue = `startingstate`

        // if voidP(startingState) then
        if (lingo_voidp(`startingstate`)).asBool() {
            // activated = 0
            self.`activated` = LingoValue.integer(0)
        } else {
            // activated = startingState
            self.`activated` = `startingstate`
        }
    }

    public func `mouseup`() -> LingoValue {
        // activated = 1
        self.`activated` = LingoValue.integer(1)
        // me.doAction()
        let _ : LingoValue = self.`doaction`()
        return .void
    }
}
```

Files whose names begin with `movie_` are treated as **movie scripts** and transpile to free functions (`lingo_<name>`) instead of class methods.

## Bytecode Decompilation

`LingoBytecode` reads Director script data structures, including script chunks, script context chunks, handler records, opcodes, property name ids, and literal stores. Its decompiler turns compiled handler bytecode back into `LingoAST.Statement` and `Expression` values, so source parsing and bytecode decompilation feed the same downstream AST model.

Callers provide the movie's resolved name table when decompiling, because the flat `Lnam` chunk is a shared Director resource outside the Lingo-specific script chunk itself.

## Bytecode VM

`LingoVM` executes compiled `HandlerDef` bytecode directly using the same `LingoRuntime` value model as transpiled Swift. It is a stack-machine interpreter with explicit inputs for the handler, script chunk, name table, arguments, optional receiver, Director file version, and `LingoEnvironment`.

Director-specific concepts are delegated through `LingoVMHost`: movie, sprite, member, menu, sound, window, object creation, sprite collision queries, and field highlighting. For tests and lightweight integrations, `HarnessHost`, `HarnessObject`, and `LingoAssembler` provide reusable host objects and bytecode-construction helpers without requiring a full Director runtime.

## Runtime

`LingoRuntime` provides the types all generated code depends on:

| Type | Role |
|---|---|
| `LingoValue` | Tagged enum: `.void`, `.integer`, `.float`, `.string`, `.symbol`, `.list`, `.propertyList`, `.object`, `.boundMethod` |
| `LingoObject` | Base class for transpiled scripts; uses `@dynamicMemberLookup` and `@dynamicCallable` |
| `LingoEnvironment` | Instance-owned global variables and global function handlers; callers decide how to scope and share each environment |

`LingoValue` implements the Lingo semantics you'd expect:
- Case-insensitive string and symbol comparisons.
- Native implicit type coercions for operators.
- 1-based indexing for strings and lists.
- Chunk expressions (`char`, `word`, `item`, `line`).
- Safe optional parameter defaults (`LingoValue.void`).

## CLI Usage

```sh
# Transpile a single file
swift run swiftlingoc path/to/Button.ls OutputDir/

# Transpile an entire directory of .ls files
swift run swiftlingoc path/to/Scripts/ OutputDir/
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
.package(url: "https://github.com/MillerTechnologyPeru/swift-lingo", branch: "master"),
```

Available products: `LingoRuntime`, `LingoAST`, `LingoParser`, `LingoTranspiler`, `LingoBytecode`, `LingoVM`, `LingoTranspilerPlugin`, `swiftlingoc`.

## Requirements

- Swift 6.3+
- macOS / Linux

## License

See [LICENSE](LICENSE).
