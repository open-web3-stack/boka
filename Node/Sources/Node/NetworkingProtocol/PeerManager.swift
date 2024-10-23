import Blockchain
import Foundation
import Networking
import Utils

public struct HeadInfo: Hashable, Sendable {
    public let headerHash: Data32
    public let timeslot: TimeslotIndex

    public init(headerHash: Data32, timeslot: TimeslotIndex) {
        self.headerHash = headerHash
        self.timeslot = timeslot
    }
}

public class PeerInfo {
    public let address: NetAddr
    public internal(set) var reputation: Int = 0
    public internal(set) var finalized: HeadInfo?
    public internal(set) var leafs: Set<HeadInfo> = []

    public init(address: NetAddr) {
        self.address = address
    }
}

public class PeerManager {
    private let peers: ThreadSafeContainer<[NetAddr: PeerInfo]> = .init([:])

    public init() {}

    public func add(address: NetAddr) {
        peers.write { peers in
            if peers.keys.contains(address) {
                return
            }
            peers[address] = PeerInfo(address: address)
        }
    }

    func updatePeer<R>(address: NetAddr, fn: (PeerInfo) -> R) -> R {
        peers.write { peers in
            if let peer = peers[address] {
                return fn(peer)
            } else {
                let peer = PeerInfo(address: address)
                peers[address] = peer
                return fn(peer)
            }
        }
    }
}
