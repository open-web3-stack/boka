import Foundation
import msquic
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

public struct NetAddr: Hashable, Sendable {
    var ipAddress: String
    var port: UInt16
    var ipv4: Bool

    public init(ipAddress: String, port: UInt16, ipv4: Bool = false) {
        self.ipAddress = ipAddress
        self.port = port
        self.ipv4 = ipv4
    }

    public init(quicAddr: QUIC_ADDR) {
        let (host, port, ipv4) = parseQuicAddr(quicAddr) ?? ("::dead:beef", 0, false)
        ipAddress = host
        self.port = port
        self.ipv4 = ipv4
    }

    func toQuicAddr() -> QUIC_ADDR? {
        var addr = QUIC_ADDR()
        let cstring = ipAddress.cString(using: .utf8)
        guard cstring != nil else {
            return nil
        }
        let success = QuicAddrFromString(cstring!, port, &addr)
        guard success == 1 else {
            return nil
        }
        return addr
    }
}

extension NetAddr: CustomStringConvertible {
    public var description: String {
        if ipv4 {
            "\(ipAddress):\(port)"
        } else {
            "[\(ipAddress)]:\(port)"
        }
    }
}

func parseQuicAddr(_ addr: QUIC_ADDR) -> (String, UInt16, Bool)? {
    let ipv6 = addr.Ip.sa_family == QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_INET6)
    let port = if ipv6 {
        CFSwapInt16BigToHost(addr.Ipv6.sin6_port)
    } else {
        CFSwapInt16BigToHost(addr.Ipv4.sin_port)
    }
    var addr = addr
    if ipv6 {
        addr.Ipv6.sin6_port = 0
    } else {
        addr.Ipv4.sin_port = 0
    }
    var buffer = QUIC_ADDR_STR()
    let success = QuicAddrToString(&addr, &buffer)
    guard success == 1 else {
        return nil
    }
    let ipaddress = withUnsafePointer(to: buffer.Address) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(64)) { ptr in
            String(cString: ptr, encoding: .utf8)!
        }
    }

    return (ipaddress, port, ipv6)
}
