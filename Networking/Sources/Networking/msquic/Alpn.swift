import Foundation
import msquic

struct Alpn {
    let protocolName: String
    let version: Int
    let genesisHeader: Data
    let _headerPrefixLength: Int = 4
    init?(_ protocolName: String = "jamnp-s", version: Int = 0, genesisHeader: Data) throws(QuicError) {
        self.protocolName = protocolName
        self.version = version
        guard genesisHeader.count >= _headerPrefixLength else {
            throw QuicError.invalidAlpn
        }
        self.genesisHeader = genesisHeader
    }

    var rawValue: QUIC_BUFFER {
        let headerPrefix = String(data: genesisHeader.prefix(_headerPrefixLength), encoding: .utf8) ?? ""
        let alpnString = "\(protocolName)/\(version)/\(headerPrefix)"
        let alpnData = alpnString.data(using: .utf8)!
        var buffer = QUIC_BUFFER()
        buffer.Length = UInt32(alpnData.count)
        alpnData.withUnsafeBytes { rawBufferPointer in
            buffer.Buffer = UnsafeMutablePointer<UInt8>(mutating: rawBufferPointer.bindMemory(to: UInt8.self).baseAddress!)
        }
        return buffer
    }

    var rawValuePointer: UnsafePointer<QUIC_BUFFER> {
        withUnsafePointer(to: rawValue) { $0 }
    }
}
