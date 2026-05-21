import Foundation

struct SandboxExecutableResolution {
    let path: String
    let isExplicit: Bool
}

enum SandboxExecutableResolver {
    private static let executableName = "boka-sandbox"
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

    static func isExecutableAvailable(at path: String) -> Bool {
        let fileManager = FileManager.default
        if path.contains("/") {
            return fileManager.isExecutableFile(atPath: path)
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for entry in pathValue.split(separator: ":") where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: String(entry), isDirectory: true)
                .appendingPathComponent(path)
                .standardizedFileURL
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return true
            }
        }

        return false
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

        for argument in CommandLine.arguments where argument.contains("/") {
            let argumentURL = URL(fileURLWithPath: argument).standardizedFileURL
            let argumentDirectory = directoryRoot(for: argumentURL)
            roots.append(contentsOf: urlsWithAncestors(start: argumentDirectory, levels: 4))
        }

        let packageRoot = packageRootFromSource()
        roots.append(contentsOf: urlsWithAncestors(start: packageRoot, levels: 2))
        roots.append(contentsOf: swiftPMBuildRoots(packageRoot: packageRoot))

        var expanded: [URL] = []
        for root in uniqueURLs(roots) {
            expanded.append(root)
            expanded.append(root.appendingPathComponent("PolkaVM", isDirectory: true))
        }

        return uniqueURLs(expanded)
    }

    private static func directoryRoot(for url: URL) -> URL {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }

        return url.deletingLastPathComponent()
    }

    private static func swiftPMBuildRoots(packageRoot: URL) -> [URL] {
        let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
        return [
            buildRoot.appendingPathComponent("debug", isDirectory: true),
            buildRoot.appendingPathComponent("release", isDirectory: true),
        ]
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
