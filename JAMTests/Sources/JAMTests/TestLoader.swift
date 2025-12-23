import Blockchain
import Foundation

public struct Testcase: CustomStringConvertible, Sendable {
    public var description: String
    public var data: Data

    public init(description: String, data: Data) {
        self.description = description
        self.data = data
    }
}

public enum TestVariants: String, CaseIterable {
    case tiny
    case full

    public var config: ProtocolConfigRef {
        switch self {
        case .tiny:
            ProtocolConfigRef.tiny
        case .full:
            ProtocolConfigRef.mainnet
        }
    }
}

public enum TestsSource: String {
    case w3f = "jamtestvectors"
    case jamduna
    case javajam
    case jamixir
    case fuzz
}

public enum TestLoader {
    public static func getTestcases(path: String, extension ext: String, src: TestsSource = .w3f) throws -> [Testcase] {
        let prefix = Bundle.module.resourcePath! + "/\(src.rawValue)/\(path)"
        let files = try FileManager.default.contentsOfDirectory(atPath: prefix)
        var filtered = files.filter { $0.hasSuffix(".\(ext)") }
        filtered.sort()
        return try filtered.map {
            let data = try Data(contentsOf: URL(fileURLWithPath: prefix + "/" + $0))
            return Testcase(description: path + "/" + $0, data: data)
        }
    }

    public static func getFile(path: String, extension ext: String, src: TestsSource = .w3f) throws -> Data {
        let path = Bundle.module.resourcePath! + "/\(src.rawValue)/\(path).\(ext)"
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
}
