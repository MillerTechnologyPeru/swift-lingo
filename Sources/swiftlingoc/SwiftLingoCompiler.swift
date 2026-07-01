import Foundation
import ArgumentParser
import LingoParser
import LingoTranspiler

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct SwiftLingoCompiler: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftlingoc",
        abstract: "A transpiler that converts Adobe Director Lingo (.ls) scripts into Swift source code."
    )

    @Argument(help: "The input .ls file or directory containing .ls files.")
    var inputPath: String

    @Argument(help: "The output directory where .swift files will be generated.")
    var outputDir: String

    mutating func run() async throws {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false

        guard fileManager.fileExists(atPath: inputPath, isDirectory: &isDir) else {
            print("Error: Input path does not exist.")
            throw ExitCode.failure
        }

        let inputURL = URL(fileURLWithPath: inputPath)
        let inputFiles = Self.collectLingoFiles(at: inputURL, isDirectory: isDir.boolValue)

        guard !inputFiles.isEmpty else {
            print("No .ls files found to transpile.")
            throw ExitCode.success
        }

        let outputURL = URL(fileURLWithPath: outputDir)
        try? fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

        var errorCount = 0

        for file in inputFiles {
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                var lexer = Lexer(input: content)
                let tokens = lexer.tokenize()
                let parser = Parser(tokens: tokens)
                let script = parser.parseScript()

                if !parser.skippedTokens.isEmpty {
                    print("Warning: \(file.lastPathComponent) had \(parser.skippedTokens.count) skipped tokens during parsing. Tokens: \(parser.skippedTokens)")
                }

                let relativePath: String
                if isDir.boolValue {
                    relativePath = file.path.replacingOccurrences(of: inputURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                } else {
                    relativePath = file.lastPathComponent
                }

                let transpiler = LingoTranspiler(
                    script: script,
                    relativePath: relativePath,
                    originalPath: file.path
                )
                let transpiledCode = await transpiler.transpile()

                let disambiguatedName = relativePath.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".ls", with: ".swift")
                let outputFile = outputURL.appendingPathComponent(disambiguatedName)

                try transpiledCode.write(to: outputFile, atomically: true, encoding: .utf8)
                print("Transpiled \(relativePath) to \(disambiguatedName)")

            } catch {
                print("Error processing \(file.lastPathComponent): \(error)")
                errorCount += 1
            }
        }

        if errorCount > 0 {
            throw ExitCode.failure
        }
    }

    private static func collectLingoFiles(at inputURL: URL, isDirectory: Bool) -> [URL] {
        guard isDirectory else {
            return inputURL.pathExtension == "ls" ? [inputURL] : []
        }
        guard let enumerator = FileManager.default.enumerator(at: inputURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var inputFiles: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "ls" {
            inputFiles.append(fileURL)
        }
        return inputFiles
    }
}
