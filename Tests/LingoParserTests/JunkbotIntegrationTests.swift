import Testing
import Foundation
@testable import LingoParser

@Suite
struct JunkbotIntegrationTests {
    
    @Test
    
    func testParseAllJunkbotFiles() throws {
        let lsFiles = JunkbotFixtures.allLingoFiles()

        #expect(lsFiles.count > 0, "Should find at least some .ls files")
        
        var failedFiles: [String] = []
        var totalTokens = 0
        var totalStatements = 0
        
        for file in lsFiles {
            do {
                let content = try String(contentsOf: file, encoding: .macOSRoman)
                var lexer = Lexer(input: content)
                let tokens = lexer.tokenize()
                
                // Let's make sure it parsed some tokens
                let meaningfulTokens = tokens.filter { $0 != .newline && $0 != .eof }
                
                let parser = Parser(tokens: tokens)
                let script = parser.parseScript()
                
                totalTokens += tokens.count
                totalStatements += script.statements.count
                
                let actualSkipped = parser.skippedTokens.filter { $0 != .newline }
                
                if script.statements.isEmpty && !meaningfulTokens.isEmpty {
                    failedFiles.append("\(file.lastPathComponent): parsed no statements but has \(meaningfulTokens.count) tokens.")
                } else if !actualSkipped.isEmpty {
                    failedFiles.append("\(file.lastPathComponent): skipped \(actualSkipped.count) tokens: \(actualSkipped.prefix(5))")
                }
            } catch {
                failedFiles.append("\(file.lastPathComponent): \(error)")
            }
        }
        
        print("Successfully processed \(lsFiles.count) files, \(totalTokens) tokens, \(totalStatements) top-level statements.")
        
        if !failedFiles.isEmpty {
            Issue.record("Failed to parse \(failedFiles.count) files:\n\(failedFiles.joined(separator: "\n"))")
        }
    }
}
