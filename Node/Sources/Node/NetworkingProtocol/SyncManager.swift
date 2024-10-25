import Blockchain
import Codec
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "SyncManager")

let BLOCK_REQUEST_BLOCK_COUNT: UInt32 = 50

// TODO:
// - pick best peer
// - remove slow one
// - sync peer rotation
// - fast sync mode (no verification)
public actor SyncManager: Sendable {
    private let blockchain: Blockchain
    private let network: Network
    private let peerManager: PeerManager

    private let subscriptions: EventSubscriptions

    // starts with bulk syncing mode, until our best have catched up with the peer best
    private var bulkSyncing = false
    private var syncContinuation: [CheckedContinuation<Void, Never>] = []

    private var networkBest: HashAndSlot?
    private var networkFinalizedBest: HashAndSlot?
    private var currentRequest: (peer: NetAddr, request: BlockRequest)?

    public init(blockchain: Blockchain, network: Network, peerManager: PeerManager, eventBus: EventBus) {
        self.blockchain = blockchain
        self.network = network
        self.peerManager = peerManager
        subscriptions = EventSubscriptions(eventBus: eventBus)

        Task {
            await subscriptions.subscribe(NetworkEvents.PeerAdded.self, id: "SyncManager.PeerAdded") { [weak self] event in
                await self?.on(peerUpdated: event.info, newBlockHeader: nil)
            }
            await subscriptions.subscribe(NetworkEvents.PeerUpdated.self, id: "SyncManager.PeerUpdated") { [weak self] event in
                await self?.on(peerUpdated: event.info, newBlockHeader: event.newBlockHeader)
            }
        }
    }

    public func waitForSyncCompletion() async {
        if !bulkSyncing {
            return
        }
        await withCheckedContinuation { continuation in
            syncContinuation.append(continuation)
        }
    }

    private func on(peerUpdated info: PeerInfo, newBlockHeader: HeaderRef?) async {
        // TODO: improve this to handle the case misbehaved peers seding us the wrong best
        if let networkBest {
            if let peerBest = info.best, peerBest.timeslot > networkBest.timeslot {
                self.networkBest = peerBest
            }
        } else {
            networkBest = info.best
        }

        if let networkFinalizedBest {
            if info.finalized.timeslot > networkFinalizedBest.timeslot {
                self.networkFinalizedBest = info.finalized
            }
        } else {
            networkFinalizedBest = info.finalized
        }

        let currentHead = await blockchain.dataProvider.bestHead

        if bulkSyncing {
            await bulkSync(currentHead: currentHead)
        } else if let newBlockHeader {
            importBlock(currentTimeslot: currentHead.timeslot, newHeader: newBlockHeader, peer: info.address)
        }
    }

    private func bulkSync(currentHead: HeadInfo) async {
        if currentRequest != nil {
            return
        }

        for (addr, info) in await peerManager.peers {
            if let peerBest = info.best, peerBest.timeslot > currentHead.timeslot {
                let request = BlockRequest(
                    hash: currentHead.hash,
                    direction: .ascendingExcludsive,
                    maxBlocks: min(BLOCK_REQUEST_BLOCK_COUNT, peerBest.timeslot - currentHead.timeslot)
                )
                currentRequest = (addr, request)
                logger.debug("bulk syncing", metadata: ["peer": "\(addr)", "request": "\(request)"])

                Task {
                    let resp = try await network.send(to: addr, message: .blockRequest(request))
                    let decoded = try JamDecoder.decode([BlockRef].self, from: resp, withConfig: blockchain.config)
                    for block in decoded {
                        try await blockchain.importBlock(block)
                    }

                    currentRequest = nil

                    let currentHead = await blockchain.dataProvider.bestHead
                    if currentHead.timeslot >= networkBest!.timeslot {
                        if bulkSyncing {
                            bulkSyncing = false
                            syncContinuation.forEach { $0.resume() }
                            syncContinuation = []
                            logger.info("bulk sync completed")
                            return
                        }
                    }

                    await bulkSync(currentHead: blockchain.dataProvider.bestHead)
                }

                break
            }
        }
    }

    private func importBlock(currentTimeslot: TimeslotIndex, newHeader: HeaderRef, peer: NetAddr) {
        let blockchain = blockchain
        let network = network
        Task.detached {
            let hasBlock = try? await blockchain.dataProvider.hasBlock(hash: newHeader.hash)
            if hasBlock != true {
                do {
                    let resp = try await network.send(to: peer, message: .blockRequest(BlockRequest(
                        hash: newHeader.hash,
                        direction: .descendingInclusive,
                        maxBlocks: max(1, newHeader.value.timeslot - currentTimeslot)
                    )))
                    let decoded = try JamDecoder.decode([BlockRef].self, from: resp, withConfig: blockchain.config)
                    // reverse to import old block first
                    for block in decoded.reversed() {
                        try await blockchain.importBlock(block)
                    }
                } catch {
                    logger.warning("block request failed", metadata: ["error": "\(error)", "peer": "\(peer)"])
                }
            }
        }
    }
}
