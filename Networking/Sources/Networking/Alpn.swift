import Foundation
import Utils

public struct Alpn: Sendable {
    public let data: Data
    private static let headerPrefixLength = 8
    init(protocolName: String = "jamnp-s", version: String = "0", genesisHeader: Data32, builder: Bool) {
        let header: String.SubSequence = genesisHeader.toHexString().prefix(Alpn.headerPrefixLength)
        data = Data(
            "\(protocolName)/\(version)/\(header)\(builder ? "/builder" : "")".utf8,
        )
    }
}
