import XCTest
@testable import LingoParser
@testable import LingoAST
import Foundation

final class RoundTripValidationTest: XCTestCase {
    let junkbotSourceDir: String = "/Users/coleman/Downloads/junkbot-code-main/files"
    
    func findAllLingoFiles() -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: junkbotSourceDir)!
        var files: [String] = []
        for case let file as String in enumerator {
            if file.hasSuffix(".ls") {
                files.append(file)
            }
        }
        return files.sorted()
    }
    
    func testAllJunkbotFilesRoundTrip() throws {
        let files = findAllLingoFiles()
        XCTAssertFalse(files.isEmpty, "Should find .ls files in \(junkbotSourceDir)")
        
        var parseFailures: [String] = []
        var reparseFailures: [String] = []
        var astMismatches: [String] = []
        var trailingNewlineSkips: [String] = []
        
        for file in files {
            let fullPath = "\(junkbotSourceDir)/\(file)"
            let source: String
            do {
                source = try String(contentsOfFile: fullPath, encoding: .utf8)
            } catch {
                parseFailures.append("\(file): unreadable - \(error)")
                continue
            }
            
            var lexer = Lexer(input: source)
            let tokens = lexer.tokenize()
            let parser = Parser(tokens: tokens)
            let script = parser.parseScript()
            
            // Only track trailing newlines as non-fatal
            if !parser.skippedTokens.isEmpty && parser.skippedTokens.allSatisfy({ $0 == .newline }) {
                trailingNewlineSkips.append("\(file): \(parser.skippedTokens.count) trailing newline(s)")
            } else if !parser.skippedTokens.isEmpty {
                parseFailures.append("\(file): initial parse skipped \(parser.skippedTokens.count) tokens")
            }
            
            let stringified = script.toLingoSource()
            
            var lexer2 = Lexer(input: stringified)
            let tokens2 = lexer2.tokenize()
            let parser2 = Parser(tokens: tokens2)
            let script2 = parser2.parseScript()
            
            // Check for skipped tokens on re-parse
            if !parser2.skippedTokens.isEmpty && parser2.skippedTokens.allSatisfy({ $0 == .newline }) {
                // Trailing newlines are acceptable
            } else if !parser2.skippedTokens.isEmpty {
                reparseFailures.append("\(file): re-parse skipped \(parser2.skippedTokens.count) tokens")
            }
            
            // Compare ASTs
            if script != script2 {
                astMismatches.append(file)
            }
        }
        
        // Report non-fatal findings
        if !trailingNewlineSkips.isEmpty {
            print("Files with trailing newline skips (\(trailingNewlineSkips.count)):")
            for f in trailingNewlineSkips { print("  \(f)") }
        }
        
        // Report actual failures
        if !parseFailures.isEmpty {
            XCTFail("Initial parse failures in \(parseFailures.count) files:\n" + parseFailures.joined(separator: "\n"))
        }
        
        if !reparseFailures.isEmpty {
            XCTFail("Re-parse failures in \(reparseFailures.count) files:\n" + reparseFailures.joined(separator: "\n"))
        }
        
        if !astMismatches.isEmpty {
            XCTFail("AST mismatches in \(astMismatches.count) files:\n" + astMismatches.joined(separator: "\n"))
        }
    }
}
