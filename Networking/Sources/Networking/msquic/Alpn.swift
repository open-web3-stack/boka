import Foundation

struct Alpn {
    private let protocolName: String
    private let version: String
    private let genesisHeader: String

    init(_ protocolName: String = "jamnp-s", version: String = "0", genesisHeader: String) throws {
        self.protocolName = protocolName
        self.version = version

        guard genesisHeader.count >= 4 else {
            throw QuicError.invalidAlpn
        }
        self.genesisHeader = genesisHeader
    }

    var alpnString: String {
        "\(protocolName)/\(version)/\(genesisHeader.prefix(4))"
    }
}
