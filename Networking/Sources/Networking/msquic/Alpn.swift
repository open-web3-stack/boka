import Foundation

struct Alpn {
    private let protocolName: String
    private let version: String
    private let genesisHeader: String
    private static let headerPrefixLength = 4
    lazy var alpnString: String = "\(protocolName)/\(version)/\(genesisHeader.prefix(Alpn.headerPrefixLength))"

    init(_ protocolName: String = "jamnp-s", version: String = "0", genesisHeader: String) throws {
        self.protocolName = protocolName
        self.version = version

        guard genesisHeader.count >= Alpn.headerPrefixLength else {
            throw QuicError.invalidAlpn
        }
        self.genesisHeader = genesisHeader
    }
}
