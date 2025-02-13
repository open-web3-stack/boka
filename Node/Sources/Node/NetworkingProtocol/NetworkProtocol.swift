// Defines the core networking protocol interface for node communication

import Foundation
import Networking
import Utils

/// Protocol defining the core networking functionality required for node communication
public protocol NetworkProtocol: Sendable {
    /// Establishes a connection to a remote peer
    /// - Parameters:
    ///   - to: The network address to connect to
    ///   - role: The role of the peer to connect as
    /// - Returns: A connection info protocol instance
    func connect(to: NetAddr, role: PeerRole) throws -> any ConnectionInfoProtocol

    /// Sends a message to a specific peer by ID
    /// - Parameters:
    ///   - to: The peer ID to send to
    ///   - message: The message to send
    /// - Returns: Response data
    func send(to: PeerId, message: CERequest) async throws -> Data

    /// Sends a message to a specific network address
    /// - Parameters:
    ///   - to: The network address to send to
    ///   - message: The message to send
    /// - Returns: Response data
    func send(to: NetAddr, message: CERequest) async throws -> Data

    /// Broadcasts a message to all connected peers
    /// - Parameters:
    ///   - kind: The type of stream to broadcast on
    ///   - message: The message to broadcast
    func broadcast(kind: UniquePresistentStreamKind, message: UPMessage)

    /// Gets the network address this node is listening on
    /// - Returns: The listening network address
    func listenAddress() throws -> NetAddr

    /// The current number of connected peers
    var peersCount: Int { get }

    /// The public key of this node's network identity
    var networkKey: String { get }

    var peerRole: PeerRole { get }
}
