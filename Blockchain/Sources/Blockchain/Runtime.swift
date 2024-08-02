// the STF
public final class Runtime {
    public enum Error: Swift.Error {
        case safroleError(SafroleError)
    }

    public let config: ProtocolConfigRef

    public init(config: ProtocolConfigRef) {
        self.config = config
    }

    public func apply(block: BlockRef, state prevState: StateRef) throws(Error) -> StateRef {
        var newState = prevState.value
        newState.lastBlock = block
        let res = newState.updateSafrole(
            slot: block.header.timeslotIndex, entropy: newState.entropyPool.0, extrinsics: block.extrinsic.tickets
        )
        switch res {
        case let .success((state: postState, epochMark: _, ticketsMark: _)):
            newState.mergeWith(postState: postState)
        case let .failure(err):
            throw .safroleError(err)
        }

        return StateRef(newState)
    }
}
