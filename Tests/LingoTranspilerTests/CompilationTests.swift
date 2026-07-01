import Testing
import Foundation
import Subprocess
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
        let generatedCode = transpiler.transpile()

        // Generate a temporary package
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LingoCompileTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let swiftLingoPath = FileManager.default.currentDirectoryPath

        let packageSwift = """
            // swift-tools-version: 6.3
            import PackageDescription

            let package = Package(
                name: "LingoCompileTest",
                dependencies: [
                    .package(name: "SwiftLingo", path: "\(swiftLingoPath)")
                ],
                targets: [
                    .executableTarget(
                        name: "LingoCompileTest",
                        dependencies: [
                            .product(name: "LingoRuntime", package: "SwiftLingo")
                        ]
                    )
                ]
            )
            """
        try packageSwift.write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let sourcesDir = tempDir.appendingPathComponent("Sources").appendingPathComponent("LingoCompileTest")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let mainSwift = """
            import LingoRuntime

            \(generatedCode)

            @main
            struct App {
                static func main() {
                    // Do nothing
                }
            }
            """
        try mainSwift.write(to: sourcesDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        // Transpile them and write to separate swift files
        for file in lsFiles {
            print("Transpiling \(file.lastPathComponent)...")
            let content = try String(contentsOf: file, encoding: .macOSRoman)
            var fileLexer = Lexer(input: content)
            let fileTokens = fileLexer.tokenize()
            let fileParser = Parser(tokens: fileTokens)
            let fileScript = fileParser.parseScript()
            let fileTranspiler = LingoTranspiler(script: fileScript, relativePath: file.lastPathComponent, originalPath: file.path)

            let fileGeneratedCode = "import LingoRuntime\n" + fileTranspiler.transpile()

            let swiftFileName = file.lastPathComponent.replacingOccurrences(of: ".ls", with: ".swift")
            let fileUrl = sourcesDir.appendingPathComponent(swiftFileName)
            try fileGeneratedCode.write(to: fileUrl, atomically: true, encoding: .utf8)
        }

        // Run swift build in a bash context using Subprocess
        let result = try await Subprocess.run(
            .name("bash"),
            arguments: ["-c", "swift build"],
            workingDirectory: tempDir.path,
            output: .string,
            error: .string
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
