import Blockchain
import Foundation

// somehow without this the GH Actions CI fails
extension Foundation.Bundle: @unchecked @retroactive Sendable {}

struct Testcase: CustomStringConvertible {
    var description: String
    var data: Data
}

enum TestVariants: String, CaseIterable {
    case tiny
    case full

    var config: ProtocolConfigRef {
        switch self {
        case .tiny:
            var tiny = ProtocolConfigRef.tiny
            tiny = tiny.mutate {
                $0.preimagePurgePeriod = 32
            }
            return tiny
        case .full:
            return ProtocolConfigRef.mainnet
        }
    }
}

enum TestsSource: String {
    case w3f = "jamtestvectors"
    case jamduna
    case javajam
    case jamixir
    case fuzz
}

enum TestLoader {
    static func getTestcases(path: String, extension ext: String, src: TestsSource = .w3f) throws -> [Testcase] {
        let prefix = Bundle.module.resourcePath! + "/\(src.rawValue)/\(path)"
        let files = try FileManager.default.contentsOfDirectory(atPath: prefix)
        var filtered = files.filter { $0.hasSuffix(".\(ext)") }
        filtered.sort()
        return try filtered.map {
            let data = try Data(contentsOf: URL(fileURLWithPath: prefix + "/" + $0))
            return Testcase(description: $0, data: data)
        }
    }

    static func getFile(path: String, extension ext: String, src: TestsSource = .w3f) throws -> Data {
        let path = Bundle.module.resourcePath! + "/\(src.rawValue)/\(path).\(ext)"
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
}
