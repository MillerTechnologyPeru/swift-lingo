import Testing
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif
@testable import LingoAST
@testable import LingoParser
@testable import LingoTranspiler

#if os(macOS) || os(Linux)

@Suite
struct CompilationTests {

    @Test
    func testGeneratedSwiftCodeCompiles() async throws {
        // Find the Lingo files
        guard let resources = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            Issue.record("Missing 'Resources' directory in test bundle")
            return
        }
        let filesDirectory = resources.appendingPathComponent("files", isDirectory: true)

        guard
            let enumerator = FileManager.default.enumerator(
                at: filesDirectory,
                includingPropertiesForKeys: nil
            )
        else {
            Issue.record("Could not enumerate files")
            return
        }

        var lsFiles: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "ls" {
                lsFiles.append(url)
            }
        }

        #expect(lsFiles.count > 0, "Should find at least some .ls files")

        // Use a simple sample script
        let sampleLingo = """
            on myHandler
                put 1 into x
                return x
            end
            """

        var lexer = Lexer(input: sampleLingo)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        let script = parser.parseScript()
        let transpiler = LingoTranspiler(script: script, relativePath: "test.ls", originalPath: "test.ls")
        let generatedCode = await transpiler.transpile()

        // Generate a temporary package
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LingoCompileTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // `swift test` from the command line runs with the package root as the
        // working directory, so a local path dependency finds the checkout
        // directly. Xcode (and other IDEs) run tests with an unrelated working
        // directory, so the same path lookup silently fails to find the
        // SwiftLingo sources. Detect that case and fall back to fetching the
        // package from GitHub instead.
        let swiftLingoPath = FileManager.default.currentDirectoryPath
        let localManifest = URL(fileURLWithPath: swiftLingoPath).appendingPathComponent("Package.swift")
        let isLocalSwiftLingoCheckout =
            (try? String(contentsOf: localManifest, encoding: .utf8))?.contains("name: \"SwiftLingo\"") ?? false

        // A local path dependency can declare its own package identity via
        // `name:`, but a URL-based dependency's identity is always derived
        // from the repo name in the URL (`swift-lingo`), regardless of the
        // manifest's `name: "SwiftLingo"` — so the `.product(package:)`
        // reference below has to match whichever identity is actually in play.
        let dependency: String
        let packageIdentity: String
        if isLocalSwiftLingoCheckout {
            dependency = ".package(name: \"SwiftLingo\", path: \"\(swiftLingoPath)\")"
            packageIdentity = "SwiftLingo"
        } else {
            dependency = ".package(url: \"https://github.com/MillerTechnologyPeru/swift-lingo\", branch: \"master\")"
            packageIdentity = "swift-lingo"
        }

        let packageSwift = """
            // swift-tools-version: 6.3
            import PackageDescription

            let package = Package(
                name: "LingoCompileTest",
                platforms: [.macOS(.v14)],
                dependencies: [
                    \(dependency)
                ],
                targets: [
                    .target(
                        name: "LingoCompileTest",
                        dependencies: [
                            .product(name: "LingoRuntime", package: "\(packageIdentity)")
                        ],
                        swiftSettings: [.swiftLanguageMode(.v5)]
                    )
                ]
            )
            """
        try packageSwift.write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let sourcesDir = tempDir.appendingPathComponent("Sources").appendingPathComponent("LingoCompileTest")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        // Write inline test as a regular source file (not main.swift to avoid top-level code issues)
        let inlineSwift = """
            import LingoRuntime

            \(generatedCode)
            """
        try inlineSwift.write(to: sourcesDir.appendingPathComponent("InlineTest.swift"), atomically: true, encoding: .utf8)

        // Transpile them and write to separate swift files
        for file in lsFiles {
            print("Transpiling \(file.lastPathComponent)...")
            let content = try String(contentsOf: file, encoding: .macOSRoman)
            var fileLexer = Lexer(input: content)
            let fileTokens = fileLexer.tokenize()
            let fileParser = Parser(tokens: fileTokens)
            let fileScript = fileParser.parseScript()
            let fileTranspiler = LingoTranspiler(script: fileScript, relativePath: file.lastPathComponent, originalPath: file.path)
            fileTranspiler.log = { print($0) }

            let fileGeneratedCode = "import LingoRuntime\n" + (await fileTranspiler.transpile())

            let swiftFileName = file.lastPathComponent.replacingOccurrences(of: ".ls", with: ".swift")
            let fileUrl = sourcesDir.appendingPathComponent(swiftFileName)
            try fileGeneratedCode.write(to: fileUrl, atomically: true, encoding: .utf8)
        }

        // Run swift build in a bash context using Subprocess
        let result = try await Subprocess.run(
            .name("bash"),
            arguments: ["-c", "swift build"],
            workingDirectory: FilePath(tempDir.path),
            output: .string(limit: 8 * 1024 * 1024),
            error: .string(limit: 8 * 1024 * 1024)
        )

        let output = result.standardOutput ?? ""
        let errorOutput = result.standardError ?? ""

        if !result.terminationStatus.isSuccess {
            print(output)
            print(errorOutput)
            Issue.record("Generated Swift code failed to compile. See console for output.")
        }

        #expect(result.terminationStatus.isSuccess)
    }
}
#endif
