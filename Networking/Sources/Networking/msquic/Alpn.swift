import Foundation

struct Alpn {
    public let alpnString: String
    private static let headerPrefixLength = 4
    init(_ protocolName: String = "jamnp-s", version: String = "0", genesisHeader: String) throws {
        guard genesisHeader.count >= Alpn.headerPrefixLength else {
            throw QuicError.invalidAlpn
        }
        alpnString = "\(protocolName)/\(version)/\(genesisHeader.prefix(Alpn.headerPrefixLength))"
    }
}
