import CHelpers
import Foundation
import msquic
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

public struct NetAddr: Sendable {
    var quicAddr: QUIC_ADDR

    public init?(address: String) {
        guard let res = parseIpv6Addr(address) ?? parseIpv4Addr(address) else {
            return nil
        }
        let (host, port) = res
        self.init(ipAddress: host, port: port)
    }

    public init?(ipAddress: String, port: UInt16) {
        guard let cstring = ipAddress.cString(using: .utf8) else {
            return nil
        }
        quicAddr = QUIC_ADDR()
        let success = QuicAddrFromString(cstring, port, &quicAddr)
        guard success == 1 else {
            return nil
        }
    }

    public init(quicAddr: QUIC_ADDR) {
        self.quicAddr = quicAddr
    }

    public func getAddressAndPort() -> (String, UInt16) {
        let (host, port, _) = parseQuicAddr(quicAddr) ?? ("::dead:beef", 0, false)
        return (host, port)
    }
}

extension NetAddr: Equatable {
    public static func == (lhs: NetAddr, rhs: NetAddr) -> Bool {
        var addr1 = lhs.quicAddr
        var addr2 = rhs.quicAddr
        return QuicAddrCompare(&addr1, &addr2) == 0
    }
}

extension NetAddr: Hashable {
    public func hash(into hasher: inout Hasher) {
        var addr = quicAddr
        let hash = QuicAddrHash(&addr)
        hasher.combine(hash)
    }
}

extension NetAddr: CustomStringConvertible {
    public var description: String {
        var buffer = QUIC_ADDR_STR()
        var addr = quicAddr
        let success = QuicAddrToString(&addr, &buffer)
        guard success == 1 else {
            return "::dead:beef"
        }
        let ipAddr = withUnsafePointer(to: buffer.Address) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(64)) { ptr in
                String(cString: ptr, encoding: .utf8)!
            }
        }
        return ipAddr
    }
}

private func parseQuicAddr(_ addr: QUIC_ADDR) -> (String, UInt16, Bool)? {
    let ipv6 = addr.Ip.sa_family == QUIC_ADDRESS_FAMILY(QUIC_ADDRESS_FAMILY_INET6)
    let port = if ipv6 {
        helper_ntohs(addr.Ipv6.sin6_port)
    } else {
        helper_ntohs(addr.Ipv4.sin_port)
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
    let ipAddr = withUnsafePointer(to: buffer.Address) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(64)) { ptr in
            String(cString: ptr, encoding: .utf8)!
        }
    }

    return (ipAddr, port, ipv6)
}

private func parseIpv6Addr(_ address: String) -> (String, UInt16)? {
    let parts = address.split(separator: "]:")
    guard parts.count == 2 else {
        return nil
    }
    let host = String(parts[0])
    let port = parts[1].dropFirst()
    guard let portNum = UInt16(port, radix: 10) else {
        return nil
    }
    return (host, portNum)
}

private func parseIpv4Addr(_ address: String) -> (String, UInt16)? {
    print(address)
    let parts = address.split(separator: ":")
    guard parts.count == 2 else {
        return nil
    }
    let host = String(parts[0])
    let port = parts[1].dropFirst()
    guard let portNum = UInt16(port, radix: 10) else {
        return nil
    }
    return (host, portNum)
}
