import Foundation
import Utils

/// Holds the state of the blockchain.
/// Includes the canonical chain as well as pending forks.
/// Assume all blocks and states are valid and have been validated.
public actor Blockchain {
    public let config: ProtocolConfigRef

    public private(set) var heads: [StateRef]
    public private(set) var finalizedHead: StateRef

    private var stateByBlockHash: [Data32: StateRef] = [:]
    private var stateByTimeslot: [TimeslotIndex: [StateRef]] = [:]

    public init(config: ProtocolConfigRef, heads: [StateRef], finalizedHead: StateRef) async {
        self.config = config
        assert(heads.contains(where: { $0 === finalizedHead }))

        self.heads = heads
        self.finalizedHead = finalizedHead

        for head in heads {
            addState(head)
        }
    }

    public var bestHead: StateRef {
        // heads with the highest timestamp / latest block
        heads.max(by: { $0.value.lastBlock.header.timeslotIndex < $1.value.lastBlock.header.timeslotIndex })!
    }

    public func newHead(_ head: StateRef) {
        // TODO: check if the parent is known
        // TODO: Update heads, by either extending an existing one or adding a new fork
        addState(head)
    }

    private func addState(_ state: StateRef) {
        stateByBlockHash[state.value.lastBlock.hash] = state
        stateByTimeslot[state.value.lastBlock.header.timeslotIndex, default: []].append(state)
    }
}

extension Blockchain {
    public subscript(hash: Data32) -> StateRef? {
        stateByBlockHash[hash]
    }

    public subscript(index: TimeslotIndex) -> [StateRef]? {
        stateByTimeslot[index]
    }
}
