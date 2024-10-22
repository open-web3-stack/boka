import Foundation
import MsQuicSwift
@testable import Networking
import Testing

struct NetAddrTests {
    @Test
    func parseValidIPv4() async throws {
        let address = "127.0.0.1:9955"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "127.0.0.1", port: 9955)
        #expect(netAddr1!.getAddressAndPort() == ("127.0.0.1", 9955))
        #expect(netAddr2!.getAddressAndPort() == ("127.0.0.1", 9955))
    }

    @Test
    func parseValidIPv6Full() async throws {
        let address = "[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "2001:0db8:85a3:0000:0000:8a2e:0370:7334", port: 8080)
        #expect(netAddr1!.getAddressAndPort() == ("2001:db8:85a3::8a2e:370:7334", 8080))
        #expect(netAddr2!.getAddressAndPort() == ("2001:db8:85a3::8a2e:370:7334", 8080))
    }

    @Test
    func parseValidIPv6Compressed() async throws {
        let address = "[2001:db8:85a3::8a2e:370:7334]:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "2001:db8:85a3::8a2e:370:7334", port: 8080)
        #expect(netAddr1 != nil)
        #expect(netAddr2 != nil)
        #expect(netAddr1!.getAddressAndPort() == ("2001:db8:85a3::8a2e:370:7334", 8080))
        #expect(netAddr2!.getAddressAndPort() == ("2001:db8:85a3::8a2e:370:7334", 8080))
    }

    @Test
    func parseValidIPv6Loopback() async throws {
        let address = "[::1]:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "::1", port: 8080)
        #expect(netAddr1!.getAddressAndPort() == ("::1", 8080))
        #expect(netAddr2!.getAddressAndPort() == ("::1", 8080))
    }

    @Test
    func parseInvalidMissingPort() async throws {
        let address = "127.0.0.1"
        let netAddr = NetAddr(address: address)
        #expect(netAddr == nil)
    }

    @Test
    func parseInvalidFormat() async throws {
        let address = "abcd:::"
        let netAddr = NetAddr(address: address)
        #expect(netAddr == nil)
    }

    @Test
    func parseInvalidPortIPv4() async throws {
        let address = "127.0.0.1:75535"
        let netAddr1 = NetAddr(address: address)
        #expect(netAddr1 == nil)
    }

    @Test
    func parseInvalidPortIPv6() async throws {
        let address = "[2001:db8::1]:75535"
        let netAddr1 = NetAddr(address: address)
        #expect(netAddr1 == nil)
    }

    @Test
    func parseInvalidIPv4Format() async throws {
        let address = "256.256.256.256:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "256.256.256.256", port: 8080)
        #expect(netAddr1 == nil)
        #expect(netAddr2 == nil)
    }

    @Test
    func parseInvalidIPv6Format() async throws {
        let address = "[2001:db8:::1]:8080"
        let netAddr1 = NetAddr(address: address)
        let netAddr2 = NetAddr(ipAddress: "2001:db8:::1", port: 8080)
        #expect(netAddr1 == nil)
        #expect(netAddr2 == nil)
    }
}
