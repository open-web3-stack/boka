import Foundation

struct NetAddr: Hashable {
    var ipAddress: String
    var port: UInt16

    // Implement the hash(into:) method
    func hash(into hasher: inout Hasher) {
        hasher.combine(ipAddress)
        hasher.combine(port)
    }

    // Implement the == operator
    static func == (lhs: NetAddr, rhs: NetAddr) -> Bool {
        lhs.ipAddress == rhs.ipAddress && lhs.port == rhs.port
    }
}

public struct QuicConfig {
    public let id: String
    public let cert: String
    public let key: String
    public let alpn: String
    public let ipAddress: String
    public let port: UInt16
}
