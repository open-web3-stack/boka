import Foundation

struct NetAddr {
    var ipAddress: String
    var port: Int
}

public struct QuicConfig {
    public let id: String
    public let cert: String
    public let key: String
    public let alpn: String
    public let ipAddress: String
    public let port: UInt16
}
