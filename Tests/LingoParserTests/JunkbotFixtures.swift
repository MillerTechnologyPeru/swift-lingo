import Foundation

/// Locates the Lingo (`.ls`) fixtures bundled with the test target.
///
/// The fixtures live under `Resources/files/<category>/*.ls` and are copied
/// verbatim into the test bundle (see `Package.swift`), so they are addressed
/// through `Bundle.module` rather than any absolute filesystem path.
enum JunkbotFixtures {
    /// Root directory of the bundled `.ls` corpus (the `files` folder).
    static var filesDirectory: URL {
        guard let resources = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            fatalError("Missing 'Resources' directory in test bundle")
        }
        return resources.appendingPathComponent("files", isDirectory: true)
    }

    /// All bundled `.ls` files, sorted by their path relative to `filesDirectory`.
    static func allLingoFiles() -> [URL] {
        let root = filesDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "ls" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// The path of `url` relative to `filesDirectory`, for stable diagnostics.
    static func relativePath(_ url: URL) -> String {
        let base = filesDirectory.path
        if url.path.hasPrefix(base) {
            return String(url.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }
}
