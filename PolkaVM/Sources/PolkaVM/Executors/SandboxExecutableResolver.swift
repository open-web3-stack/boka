import Foundation

struct SandboxExecutableResolution {
    let path: String
    let isExplicit: Bool
}

enum SandboxExecutableResolver {
    private static let executableName = "boka-sandbox"
    private static let buildSubpaths = [
        ".build/debug/boka-sandbox",
        ".build/release/boka-sandbox",
        ".build/arm64-apple-macosx/debug/boka-sandbox",
        ".build/arm64-apple-macosx/release/boka-sandbox",
        ".build/x86_64-apple-macosx/debug/boka-sandbox",
        ".build/x86_64-apple-macosx/release/boka-sandbox",
    ]
    private static let resolvedDefaultPath: String = resolveDefaultPath()

    static func resolve() -> SandboxExecutableResolution {
        if let explicitPath = ProcessInfo.processInfo.environment["BOKA_SANDBOX_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !explicitPath.isEmpty
        {
            return SandboxExecutableResolution(path: explicitPath, isExplicit: true)
        }

        return SandboxExecutableResolution(path: resolvedDefaultPath, isExplicit: false)
    }

    private static func resolveDefaultPath() -> String {
        if let pathFromPATH = lookupInPath() {
            return pathFromPATH
        }

        let fileManager = FileManager.default
        for root in candidateRoots() {
            let directCandidate = root.appendingPathComponent(executableName).standardizedFileURL.path
            if fileManager.isExecutableFile(atPath: directCandidate) {
                return directCandidate
            }

            for subpath in buildSubpaths {
                let candidate = root.appendingPathComponent(subpath).standardizedFileURL.path
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        // Last resort: let posix_spawnp search PATH at runtime.
        return executableName
    }

    private static func lookupInPath() -> String? {
        let fileManager = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""

        for entry in pathValue.split(separator: ":") where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: String(entry), isDirectory: true)
                .appendingPathComponent(executableName)
                .standardizedFileURL
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func candidateRoots() -> [URL] {
        var roots: [URL] = []
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        roots.append(contentsOf: urlsWithAncestors(start: cwd, levels: 3))

        let testExecutablePath = CommandLine.arguments.first ?? ""
        if !testExecutablePath.isEmpty {
            let testExecutableDirectory = URL(fileURLWithPath: testExecutablePath).standardizedFileURL.deletingLastPathComponent()
            roots.append(contentsOf: urlsWithAncestors(start: testExecutableDirectory, levels: 4))
        }

        let packageRoot = packageRootFromSource()
        roots.append(contentsOf: urlsWithAncestors(start: packageRoot, levels: 2))

        var expanded: [URL] = []
        for root in uniqueURLs(roots) {
            expanded.append(root)
            expanded.append(root.appendingPathComponent("PolkaVM", isDirectory: true))
        }

        return uniqueURLs(expanded)
    }

    private static func urlsWithAncestors(start: URL, levels: Int) -> [URL] {
        var urls: [URL] = []
        var current = start.standardizedFileURL
        urls.append(current)

        if levels <= 0 {
            return urls
        }

        for _ in 0 ..< levels {
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                break
            }
            urls.append(parent)
            current = parent
        }

        return urls
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                result.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }

        return result
    }

    private static func packageRootFromSource() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Executors
            .deletingLastPathComponent() // PolkaVM
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // Package root
            .standardizedFileURL
    }
}
