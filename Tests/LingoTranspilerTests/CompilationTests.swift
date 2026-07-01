import Testing
import Foundation
@testable import LingoAST
@testable import LingoParser
@testable import LingoTranspiler

#if os(macOS) || os(Linux)

@Suite
struct CompilationTests {

    @Test
    func testGeneratedSwiftCodeCompiles() throws {
        // Find the Lingo files
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

        // Run swift build
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "build"]
        process.currentDirectoryURL = tempDir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            print(output)
            Issue.record("Generated Swift code failed to compile. See console for output.")
        }

        #expect(process.terminationStatus == 0)
    }
}
#endif
