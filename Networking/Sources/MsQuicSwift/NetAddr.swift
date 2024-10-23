import CHelpers
import Foundation
import msquic

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

public struct NetAddr: Sendable, Equatable, Hashable {
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

    public static func == (lhs: NetAddr, rhs: NetAddr) -> Bool {
        var addr1 = lhs.quicAddr
        var addr2 = rhs.quicAddr
        return QuicAddrCompare(&addr1, &addr2) == 1
    }

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
    let port =
        if ipv6 {
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

private func parseIpv4Addr(_ address: String) -> (String, UInt16)? {
    let ipv4Pattern =
        #"((?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"#
    let ipv4WithPortPattern = #"(\#(ipv4Pattern)):(\d{1,5})"#

    let regex = try? NSRegularExpression(pattern: ipv4WithPortPattern, options: [])
    let range = NSRange(location: 0, length: address.utf16.count)

    if let match = regex?.firstMatch(in: address, options: [], range: range) {
        let ipRange = Range(match.range(at: 1), in: address)!
        let portRange = Range(match.range(at: 3), in: address)!

        let ip = String(address[ipRange])
        let portString = String(address[portRange])

        if let port = UInt16(portString) {
            return (ip, port)
        }
    }
    return nil
}

private func parseIpv6Addr(_ address: String) -> (String, UInt16)? {
    let ipv6Pattern = [
        "(?:",
        "(?:(?:[0-9A-Fa-f]{1,4}:){6}",
        "|::(?:[0-9A-Fa-f]{1,4}:){5}",
        "|(?:[0-9A-Fa-f]{1,4})?::(?:[0-9A-Fa-f]{1,4}:){4}",
        "|(?:(?:[0-9A-Fa-f]{1,4}:){0,1}[0-9A-Fa-f]{1,4})?::(?:[0-9A-Fa-f]{1,4}:){3}",
        "|(?:(?:[0-9A-Fa-f]{1,4}:){0,2}[0-9A-Fa-f]{1,4})?::(?:[0-9A-Fa-f]{1,4}:){2}",
        "|(?:(?:[0-9A-Fa-f]{1,4}:){0,3}[0-9A-Fa-f]{1,4})?::[0-9A-Fa-f]{1,4}:",
        "|(?:(?:[0-9A-Fa-f]{1,4}:){0,4}[0-9A-Fa-f]{1,4})?::)",
        "(?:",
        "[0-9A-Fa-f]{1,4}:[0-9A-Fa-f]{1,4}",
        "|(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}",
        "(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)",
        ")",
        "|(?:(?:[0-9A-Fa-f]{1,4}:){0,5}[0-9A-Fa-f]{1,4})?::[0-9A-Fa-f]{1,4}",
        "|(?:(?:[0-9A-Fa-f]{1,4}:){0,6}[0-9A-Fa-f]{1,4})?::",
        ")",
    ].reduce("", +)
    let ipv6WithPortPattern = #"\[(\#(ipv6Pattern))\]:(\d{1,5})"#

    let regex = try? NSRegularExpression(pattern: ipv6WithPortPattern, options: [])
    let range = NSRange(location: 0, length: address.utf16.count)

    if let match = regex?.firstMatch(in: address, options: [], range: range) {
        let ipRange = Range(match.range(at: 1), in: address)!
        let portRange = Range(match.range(at: 2), in: address)!

        let ip = String(address[ipRange])
        let portString = String(address[portRange])

        if let port = UInt16(portString) {
            return (ip, port)
        }
    }
    return nil
}
