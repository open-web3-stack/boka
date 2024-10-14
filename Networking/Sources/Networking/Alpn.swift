import Foundation
import Utils

public struct Alpn {
    public let data: Data
    private static let headerPrefixLength = 8
    init(_ protocolName: String = "jamnp-s", version: String = "0", genesisHeader: Data32) {
        data = Data("\(protocolName)/\(version)/\(genesisHeader.toHexString().prefix(Alpn.headerPrefixLength))".utf8)
    }
}
