import Foundation

// somehow without this the GH Actions CI fails
extension Foundation.Bundle: @unchecked @retroactive Sendable {}

enum TestLoader {
    static func getTestFiles(path: String, extension ext: String) throws -> [(path: String, description: String)] {
        let prefix = Bundle.module.resourcePath! + "/jamtestvectors/\(path)"
        let files = try FileManager.default.contentsOfDirectory(atPath: prefix)
        var filtered = files.filter { $0.hasSuffix(".\(ext)") }
        filtered.sort()
        return filtered.map { (path: prefix + "/" + $0, description: $0) }
    }
}
