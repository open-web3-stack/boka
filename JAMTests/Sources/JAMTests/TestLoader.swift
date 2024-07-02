import Foundation

enum TestLoader {
    static func discover(forPath path: String) throws {
        let prefix = Bundle.module.bundlePath + "/jamtestvectors/\(path)"
        print("Discovering tests in \(prefix)")
        let files = try FileManager.default.contentsOfDirectory(atPath: prefix)
        var scaleFiles = files.filter { $0.hasSuffix(".scale") }
        scaleFiles.sort()
        print(scaleFiles)
    }
}
