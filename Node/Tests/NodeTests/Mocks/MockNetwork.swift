// Mock implementation of NetworkProtocol for testing

import Foundation
import Networking
import Node
import Utils

struct MockNetworkState {
    var calls: [MockNetwork.Call] = []

    // MARK: - Configuration

    var shouldFailNextSend = false
    var simulatedPeersCount = 0
    var simulatedNetworkKey = "mock_network_key"
    var simulatedListenAddress = NetAddr(address: "127.0.0.1:8000")!
    var simulatedPeerRole: PeerRole = .builder
    var simulatedResponseData: [Data] = []
}

final class MockNetwork: NetworkProtocol {
    let handler: NetworkProtocolHandler

    init(handler: NetworkProtocolHandler) {
        self.handler = handler
    }

    // MARK: - Call Tracking

    struct Call: Equatable {
        let function: String
        let parameters: [String: Any]

        static func == (lhs: Call, rhs: Call) -> Bool {
            lhs.function == rhs.function
            // Note: parameters comparison omitted since Any can't be directly compared
        }
    }

    let state: ThreadSafeContainer<MockNetworkState> = .init(.init())

    // MARK: - NetworkProtocol Implementation

    func connect(to address: NetAddr, role: PeerRole) throws -> any ConnectionInfoProtocol {
        let shouldFailNextSend = state.write {
            $0.calls.append(Call(function: "connect", parameters: ["address": address, "role": role]))
            return $0.shouldFailNextSend
        }
        if shouldFailNextSend { throw NetworkError.connectionFailed }
        return MockConnectionInfo(role: role, remoteAddress: address, publicKey: Data(repeating: 0, count: 32))
    }

    func send(to peerId: PeerId, message: CERequest) async throws -> [Data] {
        let (shouldFailNextSend, simulatedResponseData) = state.write {
            $0.calls.append(Call(function: "sendToPeer", parameters: ["peerId": peerId, "message": message]))
            return ($0.shouldFailNextSend, $0.simulatedResponseData)
        }
        if shouldFailNextSend { throw NetworkError.sendFailed }
        return simulatedResponseData
    }

    func send(to address: NetAddr, message: CERequest) async throws -> [Data] {
        let (shouldFailNextSend, simulatedResponseData) = state.write {
            $0.calls.append(Call(function: "sendToAddress", parameters: ["address": address, "message": message]))
            return ($0.shouldFailNextSend, $0.simulatedResponseData)
        }
        if shouldFailNextSend { throw NetworkError.sendFailed }
        return simulatedResponseData
    }

    nonisolated func broadcast(kind: UniquePresistentStreamKind, message: UPMessage) {
        state.write {
            $0.calls.append(Call(function: "broadcast", parameters: ["kind": kind, "message": message]))
        }
    }

    nonisolated func listenAddress() throws -> NetAddr {
        let (shouldFailNextSend, simulatedListenAddress) = state.write {
            $0.calls.append(Call(function: "listenAddress", parameters: [:]))
            return ($0.shouldFailNextSend, $0.simulatedListenAddress)
        }
        if shouldFailNextSend { throw NetworkError.addressNotAvailable }
        return simulatedListenAddress
    }

    var peersCount: Int {
        state.read { $0.simulatedPeersCount }
    }

    var networkKey: String {
        state.read { $0.simulatedNetworkKey }
    }

    var peerRole: PeerRole {
        state.read { $0.simulatedPeerRole }
    }

    var calls: [Call] {
        state.read { $0.calls }
    }

    func contain(calls toCheck: [MockNetwork.Call]) -> Bool {
        let calls = state.read { $0.calls }

        var idx = 0

        for call in calls {
            if idx >= toCheck.count {
                return true
            }
            let expected = toCheck[idx]

            if call.function != expected.function {
                continue
            }

            // Simple parameter matching - just check keys exist
            let match = expected.parameters.allSatisfy { key, _ in
                call.parameters[key] != nil
            }

            if !match {
                continue
            }

            idx += 1
        }

        return idx >= toCheck.count
    }
}

// MARK: - Supporting Types

enum NetworkError: Error {
    case connectionFailed
    case sendFailed
    case addressNotAvailable
}

final class MockConnectionInfo: ConnectionInfoProtocol {
    var id: Utils.UniqueId = "MockConnectionInfo"

    var role: PeerRole

    var remoteAddress: NetAddr

    var publicKey: Data?

    func ready() async throws {}

    init(role: Networking.PeerRole, remoteAddress: Networking.NetAddr, publicKey: Data?) {
        self.role = role
        self.remoteAddress = remoteAddress
        self.publicKey = publicKey
    }
}
