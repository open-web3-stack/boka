import Foundation

// somehow without this the GH Actions CI fails
// extension Foundation.Bundle: @unchecked @retroactive Sendable {}

enum TestLoader {
    static func getTestFiles(path: String, extension ext: String) throws -> [String] {
        let prefix = Bundle.module.bundlePath + "/jamtestvectors/\(path)"
        let files = try FileManager.default.contentsOfDirectory(atPath: prefix)
        var filtered = files.filter { $0.hasSuffix(".\(ext)") }
        filtered.sort()
        return filtered.map { prefix + "/" + $0 }
    }
}
