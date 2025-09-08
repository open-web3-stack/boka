import Foundation

// Public helpers to expose W3F testcases for external benchmark targets.
public enum JAMBenchSupport {
    // Loads W3F testcases from the embedded resources within the JAMTests module.
    public static func w3fTestcases(at path: String, ext: String = "bin") throws -> [Testcase] {
        try TestLoader.getTestcases(path: path, extension: ext, src: .w3f)
    }

    // Load a single W3F resource file (e.g. a companion JSON).
    public static func w3fFile(at path: String, ext: String) throws -> Data {
        try TestLoader.getFile(path: path, extension: ext, src: .w3f)
    }
}
