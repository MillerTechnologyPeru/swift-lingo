import PackagePlugin
import Foundation

@main
struct LingoTranspilerPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let lingoc = try context.tool(named: "swiftlingoc")
        let outputDir = context.pluginWorkDirectory.appending("GeneratedLingo")

        // Find all .ls files in the target
        let lsFiles = sourceTarget.sourceFiles.filter { $0.path.extension == "ls" }
        guard !lsFiles.isEmpty else { return [] }

        // Since lingoc currently takes a directory or file, and outputs to a directory
        // We will just pass the target's root directory, and the tool will scan and disambiguate.
        // Wait, the source files might be scattered. We'll pass the target's directory.
        // And swiftlingoc will process them all.

        let inputDir = sourceTarget.directory

        // Output files we expect to be generated (for the build system to track)
        // To accurately track, we need to know the generated filenames.
        // Our CLI disambiguates by relative path.
        var outputFiles: [Path] = []
        for file in lsFiles {
            let relativeString = file.path.string.replacingOccurrences(of: inputDir.string + "/", with: "")
            let disambiguatedName = relativeString.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".ls", with: ".swift")
            outputFiles.append(outputDir.appending(disambiguatedName))
        }

        return [
            .buildCommand(
                displayName: "Transpiling Lingo scripts",
                executable: lingoc.path,
                arguments: [
                    inputDir.string,
                    outputDir.string
                ],
                inputFiles: lsFiles.map { $0.path },
                outputFiles: outputFiles
            )
        ]
    }
}
