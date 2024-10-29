import Blockchain
import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "PeerManager")

public struct PeerInfo: Sendable {
    public let id: PeerId
    public internal(set) var finalized: HashAndSlot
    public internal(set) var heads: Set<HashAndSlot> = []

    public var best: HashAndSlot? {
        heads.max { $0.timeslot < $1.timeslot }
    }
}

// TODOs:
// - distinguish between connect peers and offline peers
// - peer reputation
// - purge offline peers
public actor PeerManager: Sendable {
    private let eventBus: EventBus

    public private(set) var peers: [Data: PeerInfo] = [:]

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func addPeer(id: PeerId, handshake: BlockAnnouncementHandshake) {
        var peer = PeerInfo(
            id: id,
            finalized: handshake.finalized
        )
        for head in handshake.heads {
            peer.heads.insert(head)
        }
        peers[id.publicKey] = peer

        logger.debug("added peer", metadata: ["address": "\(id.address)", "publicKey": "\(id.publicKey)", "finalized": "\(peer.finalized)"])
        eventBus.publish(NetworkEvents.PeerAdded(info: peer))
    }

    func updatePeer(id: PeerId, message: BlockAnnouncement) {
        let updatedPeer: PeerInfo
        if var peer = peers[id.publicKey] {
            peer.finalized = message.finalized
            // purge heads that are older than the finalized head
            // or if it is the parent of the new block
            // this means if some blocks are skipped, it is possible that we miss purge some heads
            // that is ancestor of the new block. but that's fine
            peer.heads = peer.heads.filter { head in
                head.timeslot > message.finalized.timeslot && head.hash != message.header.value.parentHash
            }
            peer.heads.insert(HashAndSlot(hash: message.header.hash, timeslot: message.header.value.timeslot))
            updatedPeer = peer
        } else {
            // this shouldn't happen but let's handle it
            updatedPeer = PeerInfo(
                id: id,
                finalized: message.finalized,
                heads: [
                    HashAndSlot(hash: message.header.hash, timeslot: message.header.value.timeslot),
                ]
            )
        }
        peers[id.publicKey] = updatedPeer

        logger.debug("updated peer", metadata: [
            "address": "\(id.address)", "publicKey": "\(id.publicKey)", "finalized": "\(updatedPeer.finalized)",
        ])
        eventBus.publish(NetworkEvents.PeerUpdated(info: updatedPeer, newBlockHeader: message.header))
    }
}
