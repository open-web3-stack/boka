import Utils

extension State {
    public static func devGenesis(config: ProtocolConfigRef) throws -> (StateRef, BlockRef) {
        var devKeys = [ValidatorKey]()

        var state = State.dummy(config: config)

        for i in 0 ..< config.value.totalNumberOfValidators {
            let keySet = try DevKeyStore.getDevKey(seed: UInt32(i))
            let addr = "127.0.0.1:\(UInt16(i + 5000))"
            var addrData = Data(addr.utf8)
            addrData.append(contentsOf: Data(repeating: 0, count: 128 - addrData.count))
            devKeys.append(ValidatorKey(
                bandersnatch: keySet.bandersnatch.data,
                ed25519: keySet.ed25519.data,
                bls: keySet.bls.data,
                metadata: Data128(addrData)!
            ))
        }
        state.safroleState.nextValidators = try ConfigFixedSizeArray(config: config, array: devKeys)
        state.validatorQueue = try ConfigFixedSizeArray(config: config, array: devKeys)
        state.currentValidators = try ConfigFixedSizeArray(config: config, array: devKeys)

        var epochKeys = [BandersnatchPublicKey]()
        for i in 0 ..< config.value.epochLength {
            epochKeys.append(devKeys[i % config.value.totalNumberOfValidators].bandersnatch)
        }
        state.safroleState.ticketsOrKeys = try .right(ConfigFixedSizeArray(config: config, array: epochKeys))

        let ctx = try Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))
        let commitment = try Bandersnatch.RingCommitment(
            ring: devKeys.map { try Bandersnatch.PublicKey(data: $0.bandersnatch) },
            ctx: ctx
        )
        state.safroleState.ticketsVerifier = commitment.data

        let block = BlockRef(Block.dummy(config: config))
        try state.recentHistory.items.append(RecentHistory.HistoryItem(
            headerHash: block.hash,
            superPeak: Data32(),
            stateRoot: Data32(),
            lookup: [Data32: Data32]()
        ))

        return (StateRef(state), block)
    }
}
