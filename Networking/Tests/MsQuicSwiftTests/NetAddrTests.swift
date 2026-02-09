import Foundation
@testable import MsQuicSwift
import Testing
import TracingUtils
import Utils

struct NetAddrTests {
    private func expectAddress(_ netAddr: NetAddr?, ip: String, port: UInt16) {
        let addr = netAddr?.getAddressAndPort()
        #expect(addr?.0 == ip)
        #expect(addr?.1 == port)
    }

    @Test
    func parseValidIPv4() {
        let address = "127.0.0.1:9955"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "127.0.0.1", port: 9955)
        expectAddress(netAddr1, ip: "127.0.0.1", port: 9955)
        expectAddress(netAddr2, ip: "127.0.0.1", port: 9955)
    }

    @Test
    func parseValidIPv6Full() {
        let address = "[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "2001:0db8:85a3:0000:0000:8a2e:0370:7334", port: 8080)
        expectAddress(netAddr1, ip: "2001:db8:85a3::8a2e:370:7334", port: 8080)
        expectAddress(netAddr2, ip: "2001:db8:85a3::8a2e:370:7334", port: 8080)
    }

    @Test
    func parseValidIPv6Compressed() {
        let address = "[2001:db8:85a3::8a2e:370:7334]:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "2001:db8:85a3::8a2e:370:7334", port: 8080)
        #expect(netAddr1 != nil)
        #expect(netAddr2 != nil)
        expectAddress(netAddr1, ip: "2001:db8:85a3::8a2e:370:7334", port: 8080)
        expectAddress(netAddr2, ip: "2001:db8:85a3::8a2e:370:7334", port: 8080)
    }

    @Test
    func parseValidIPv6Loopback() {
        let address = "[::1]:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "::1", port: 8080)
        expectAddress(netAddr1, ip: "::1", port: 8080)
        expectAddress(netAddr2, ip: "::1", port: 8080)
    }

    @Test
    func parseInvalidMissingPort() {
        let address = "127.0.0.1"
        let netAddr = NetAddr(address: address)
        #expect(netAddr == nil)
    }

    @Test
    func parseInvalidFormat() {
        let address1 = "abcd:::"
        let netAddr1 = NetAddr(address: address1)
        #expect(netAddr1 == nil)
        let address2 = "127.0.0.1:12,awef"
        let netAddr2 = NetAddr(address: address2)
        #expect(netAddr2 == nil)
        let address3 = "[2001:db8:85a3::8a2e:370:7334]:8080,8081,8082"
        let netAddr3 = NetAddr(address: address3)
        #expect(netAddr3 == nil)
    }

    @Test
    func parseInvalidPortIPv4() {
        let address = "127.0.0.1:75535"
        let netAddr1 = NetAddr(address: address)
        #expect(netAddr1 == nil)
    }

    @Test
    func parseInvalidPortIPv6() {
        let address = "[2001:db8::1]:75535"
        let netAddr1 = NetAddr(address: address)
        #expect(netAddr1 == nil)
    }

    @Test
    func parseInvalidIPv4Format() {
        let address = "256.256.256.256:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "256.256.256.256", port: 8080)
        #expect(netAddr1 == nil)
        #expect(netAddr2 == nil)
    }

    @Test
    func parseInvalidIPv6Format() {
        let address = "[2001:db8:::1]:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "2001:db8:::1", port: 8080)
        #expect(netAddr1 == nil)
        #expect(netAddr2 == nil)
    }
}
