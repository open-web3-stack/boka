import Foundation

#if compiler(>=6.0)
    extension TestLoader {
        func test() {
            #error(">= 6.0")
        }
    }
#else
    extension TestLoader {
        func test() {
            #error("< 6.0")
        }
    }
#endif

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
