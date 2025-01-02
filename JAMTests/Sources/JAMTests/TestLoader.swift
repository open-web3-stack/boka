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
            ProtocolConfigRef.tiny
        case .full:
            ProtocolConfigRef.mainnet
        }
    }
}

enum TestVectorSource: String {
    case jamtestvectors
    case jamtestnet
}

enum TestLoader {
    static func getFilenames(path: String, extension ext: String, src: TestVectorSource = .jamtestvectors) throws -> [String] {
        let prefix = Bundle.module.resourcePath! + "/\(src.rawValue)/\(path)"
        let files = try FileManager.default.contentsOfDirectory(atPath: prefix)
        var filtered = files.filter { $0.hasSuffix(".\(ext)") }
        filtered.sort()
        return filtered
    }

    static func getTestcases(path: String, extension ext: String, src: TestVectorSource = .jamtestvectors) throws -> [Testcase] {
        let prefix = Bundle.module.resourcePath! + "/\(src.rawValue)/\(path)"
        let files = try getFilenames(path: path, extension: ext, src: src)
        return try files.map {
            let data = try Data(contentsOf: URL(fileURLWithPath: prefix + "/" + $0))
            return Testcase(description: $0, data: data)
        }
    }

    static func getFile(path: String, extension ext: String, src: TestVectorSource = .jamtestvectors) throws -> Data {
        let path = Bundle.module.resourcePath! + "/\(src.rawValue)/\(path).\(ext)"
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
}
