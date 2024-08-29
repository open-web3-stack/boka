import Foundation
import msquic

struct Alpn {
    private let protocolName: Data
    private let version: Int
    private let genesisHeader: Data
    private let headerPrefixLength: Int = 4
    init(_ protocolName: Data = Data("jamnp-s".utf8), version: Int = 0, genesisHeader: Data)
        throws(QuicError)
    {
        self.protocolName = protocolName
        self.version = version
        guard genesisHeader.count >= headerPrefixLength else {
            throw QuicError.invalidAlpn
        }
        self.genesisHeader = genesisHeader
    }

    var alpnString: String {
        let protocolString = data2String(data: protocolName)
        let headerPrefix = data2String(data: genesisHeader.prefix(headerPrefixLength))
        return "\(protocolString)/\(version)/\(headerPrefix)"
    }

    func data2String(data: Data) -> String {
        let uint8Array = [UInt8](data)
        let characters = uint8Array.map { Character(UnicodeScalar($0)) }
        return String(characters)
    }

    var rawValue: QUIC_BUFFER {
        let alpnData = alpnString.data(using: .utf8)!
        var buffer = QUIC_BUFFER()
        buffer.Length = UInt32(alpnData.count)
        alpnData.withUnsafeBytes { rawBufferPointer in
            buffer.Buffer = UnsafeMutablePointer<UInt8>(
                mutating: rawBufferPointer.bindMemory(to: UInt8.self).baseAddress!
            )
        }
        return buffer
    }

    var rawValuePointer: UnsafePointer<QUIC_BUFFER> {
        withUnsafePointer(to: rawValue) { $0 }
    }
}
