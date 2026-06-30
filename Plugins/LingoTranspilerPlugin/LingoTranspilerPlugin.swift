import PackagePlugin
import Foundation

@main
struct LingoTranspilerPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let lingoc = try context.tool(named: "swiftlingoc")
        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("GeneratedLingo")

        // Find all .ls files in the target
        let lsFiles = sourceTarget.sourceFiles.filter { $0.url.pathExtension == "ls" }
        guard !lsFiles.isEmpty else { return [] }

        // Since lingoc currently takes a directory or file, and outputs to a directory
        // We will just pass the target's root directory, and the tool will scan and disambiguate.
        // Wait, the source files might be scattered. We'll pass the target's directory.
        // And swiftlingoc will process them all.

        let inputDir = sourceTarget.directoryURL

        // Output files we expect to be generated (for the build system to track)
        // To accurately track, we need to know the generated filenames.
        // Our CLI disambiguates by relative path.
        var outputFiles: [URL] = []
        for file in lsFiles {
            let relativeString = file.url.path.replacingOccurrences(of: inputDir.path + "/", with: "")
            let disambiguatedName = relativeString.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".ls", with: ".swift")
            outputFiles.append(outputDir.appendingPathComponent(disambiguatedName))
        }

        return [
            .buildCommand(
                displayName: "Transpiling Lingo scripts",
                executable: lingoc.url,
                arguments: [
                    inputDir.path,
                    outputDir.path
                ],
                inputFiles: lsFiles.map { $0.url },
                outputFiles: outputFiles
            )
        ]
    }
}
