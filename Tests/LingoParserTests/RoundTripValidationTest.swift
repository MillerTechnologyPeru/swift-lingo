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
    
    func isNewlineToken(_ token: Token) -> Bool {
        if case .newline = token { return true }
        return false
    }
    
    func testAllJunkbotFilesParse() throws {
        let files = findAllLingoFiles()
        XCTAssertFalse(files.isEmpty, "Should find .ls files in \(junkbotSourceDir)")
        
        var failures: [String] = []
        var parseSkipped: [String] = []
        
        for file in files {
            let fullPath = "\(junkbotSourceDir)/\(file)"
            let source: String
            do {
                source = try String(contentsOfFile: fullPath, encoding: .utf8)
            } catch {
                failures.append("\(file): unreadable - \(error)")
                continue
            }
            
            var lexer = Lexer(input: source)
            let tokens = lexer.tokenize()
            let parser = Parser(tokens: tokens)
            let script = parser.parseScript()
            
            if !parser.skippedTokens.isEmpty {
                let nonNewlineSkips = parser.skippedTokens.filter { !isNewlineToken($0) }
                if !nonNewlineSkips.isEmpty {
                    failures.append("\(file): skipped \(nonNewlineSkips.count) non-newline tokens: \(nonNewlineSkips)")
                } else {
                    parseSkipped.append("\(file): \(parser.skippedTokens.count) trailing newlines skipped")
                }
            }
            
            let stringified = script.toLingoSource()
            
            var lexer2 = Lexer(input: stringified)
            let tokens2 = lexer2.tokenize()
            let parser2 = Parser(tokens: tokens2)
            let _ = parser2.parseScript()
            
            if !parser2.skippedTokens.isEmpty {
                let nonNewlineSkips = parser2.skippedTokens.filter { !isNewlineToken($0) }
                if !nonNewlineSkips.isEmpty {
                    failures.append("\(file): re-parse skipped \(nonNewlineSkips.count) non-newline tokens: \(nonNewlineSkips)")
                }
            }
        }
        
        print("Files with only trailing newline skips (\(parseSkipped.count)):")
        for f in parseSkipped { print("  \(f)") }
        
        if !failures.isEmpty {
            XCTFail("Failures in \(failures.count) files:\n" + failures.joined(separator: "\n"))
        }
    }
}
