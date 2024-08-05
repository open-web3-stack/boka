import Utils

// the STF
public final class Runtime {
    public enum Error: Swift.Error {
        case safroleError(SafroleError)
        case invalidValidatorEd25519Key
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

        newState.activityStatistics = updateValidatorActivityStatistics(block: block, state: prevState)

        return StateRef(newState)
    }

    // TODO: add tests
    public func updateValidatorActivityStatistics(block: BlockRef, state: StateRef) -> ValidatorActivityStatistics {
        let epochLength = UInt32(config.value.epochLength)
        let currentEpoch = state.value.timeslot / epochLength
        let newEpoch = block.header.timeslotIndex / epochLength
        let isEpochChange = currentEpoch != newEpoch

        var acc = isEpochChange ? ConfigFixedSizeArray<_, ProtocolConfig.TotalNumberOfValidators>(
            config: config, defaultValue: ValidatorActivityStatistics.StatisticsItem.dummy(config: config)
        ) : state.value.activityStatistics.accumulator

        let prev = isEpochChange ? state.value.activityStatistics.accumulator : state.value.activityStatistics.previous

        var item = acc[block.header.authorIndex]
        item.blocks += 1
        item.tickets += UInt32(block.extrinsic.tickets.tickets.count)
        item.preimages += UInt32(block.extrinsic.preimages.preimages.count)
        item.preimagesBytes += UInt32(block.extrinsic.preimages.preimages.reduce(into: 0) { $0 += $1.size })

        acc[block.header.authorIndex] = item

        for report in block.extrinsic.reports.guarantees {
            for cred in report.credential {
                acc[cred.index].guarantees += 1
            }
        }

        for assurance in block.extrinsic.availability.assurances {
            acc[assurance.validatorIndex].assurances += 1
        }

        return ValidatorActivityStatistics(
            accumulator: acc,
            previous: prev
        )
    }
}
