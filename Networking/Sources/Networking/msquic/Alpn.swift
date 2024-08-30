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

    private func data2String(data: Data) -> String {
        let uint8Array = [UInt8](data)
        let characters = uint8Array.map { Character(UnicodeScalar($0)) }
        return String(characters)
    }

    var rawValue: QuicBuffer {
        let alpnData = alpnString.data(using: .utf8)!
        let count = alpnData.count
        return QuicBuffer(
            Length: UInt32(count),
            Buffer: alpnData.withUnsafeBytes { bytes -> UnsafeMutablePointer<UInt8> in
                let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
                pointer.initialize(
                    from: bytes.bindMemory(to: UInt8.self).baseAddress!, count: count
                )
                return pointer
            }
        )
    }
}
