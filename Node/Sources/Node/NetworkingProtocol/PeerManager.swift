import Blockchain
import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "PeerManager")

public struct PeerInfo {
    public let address: NetAddr
    public internal(set) var finalized: HashAndSlot
    public internal(set) var heads: Set<HashAndSlot> = []
}

public actor PeerManager: Sendable {
    private var peers: [NetAddr: PeerInfo] = [:]

    init() {}

    func addPeer(address: NetAddr, handshake: BlockAnnouncementHandshake) {
        var peer = PeerInfo(
            address: address,
            finalized: handshake.finalized
        )
        for head in handshake.heads {
            peer.heads.insert(head)
        }
        peers[address] = peer

        logger.debug("added peer", metadata: ["address": "\(address)", "finalized": "\(peer.finalized)"])
    }

    func updatePeer(address: NetAddr, message: BlockAnnouncement) {
        if var peer = peers[address] {
            peer.finalized = message.finalized
            // purge heads that are older than the finalized head
            // or if it is the parent of the new block
            // this means if some blocks are skipped, it is possible that we miss purge some heads
            // that is ancestor of the new block. but that's fine
            peer.heads = peer.heads.filter { head in
                head.timeslot > message.finalized.timeslot && head.hash != message.header.parentHash
            }
            peer.heads.insert(HashAndSlot(hash: message.header.hash(), timeslot: message.header.timeslot))
            peers[address] = peer
        } else {
            // this shouldn't happen but let's handle it
            peers[address] = PeerInfo(
                address: address,
                finalized: message.finalized,
                heads: [
                    HashAndSlot(hash: message.header.hash(), timeslot: message.header.timeslot),
                ]
            )
        }

        logger.debug("updated peer", metadata: ["address": "\(address)", "finalized": "\(peers[address]!.finalized)"])
    }

    public func getPeer(address: NetAddr) -> PeerInfo? {
        peers[address]
    }
}
