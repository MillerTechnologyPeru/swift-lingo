import Testing
import Foundation
@testable import LingoParser
@testable import LingoAST

@Suite
struct RoundTripValidationTests {

    private struct Findings: Sendable {
        var parseFailures: [String] = []
        var reparseFailures: [String] = []
        var astMismatches: [String] = []
        var trailingNewlineSkips: [String] = []
    }

    @Test
    func allJunkbotFilesRoundTrip() async throws {
        let files = JunkbotFixtures.allLingoFiles()
        #expect(!files.isEmpty, "Should find .ls files in the test bundle")

        var findings = Findings()

        for file in files {
            let name = JunkbotFixtures.relativePath(file)
            let source: String
            do {
                source = try String(contentsOf: file, encoding: .utf8)
            } catch {
                findings.parseFailures.append("\(name): unreadable - \(error)")
                continue
            }

            var lexer = Lexer(input: source)
            let tokens = lexer.tokenize()
            let parser = Parser(tokens: tokens)
            let script = parser.parseScript()

            // Only track trailing newlines as non-fatal
            if !parser.skippedTokens.isEmpty && parser.skippedTokens.allSatisfy({ $0 == .newline }) {
                findings.trailingNewlineSkips.append("\(name): \(parser.skippedTokens.count) trailing newline(s)")
            } else if !parser.skippedTokens.isEmpty {
                findings.parseFailures.append("\(name): initial parse skipped \(parser.skippedTokens.count) tokens")
            }

            let stringified = await script.toLingoSource()

            var lexer2 = Lexer(input: stringified)
            let tokens2 = lexer2.tokenize()
            let parser2 = Parser(tokens: tokens2)
            let script2 = parser2.parseScript()

            // Check for skipped tokens on re-parse
            if !parser2.skippedTokens.isEmpty && parser2.skippedTokens.allSatisfy({ $0 == .newline }) {
                // Trailing newlines are acceptable
            } else if !parser2.skippedTokens.isEmpty {
                findings.reparseFailures.append("\(name): re-parse skipped \(parser2.skippedTokens.count) tokens")
            }

            // Compare ASTs
            if script != script2 {
                findings.astMismatches.append(name)
            }
        }

        // Report non-fatal findings
        if !findings.trailingNewlineSkips.isEmpty {
            print("Files with trailing newline skips (\(findings.trailingNewlineSkips.count)):")
            for f in findings.trailingNewlineSkips { print("  \(f)") }
        }

        // Report actual failures
        #expect(findings.parseFailures.isEmpty, "Initial parse failures in \(findings.parseFailures.count) files:\n\(findings.parseFailures.joined(separator: "\n"))")
        #expect(findings.reparseFailures.isEmpty, "Re-parse failures in \(findings.reparseFailures.count) files:\n\(findings.reparseFailures.joined(separator: "\n"))")
        #expect(findings.astMismatches.isEmpty, "AST mismatches in \(findings.astMismatches.count) files:\n\(findings.astMismatches.joined(separator: "\n"))")
    }
}
