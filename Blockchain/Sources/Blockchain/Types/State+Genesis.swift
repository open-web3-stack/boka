import Utils

extension State {
    public static func devGenesis(config: ProtocolConfigRef) throws -> State {
        var devKeys = [ValidatorKey]()

        var state = State.dummy(config: config)

        for i in 0 ..< config.value.totalNumberOfValidators {
            let keySet = try DevKeyStore.getDevKey(seed: UInt32(i))
            devKeys.append(ValidatorKey(
                bandersnatch: keySet.bandersnatch.data,
                ed25519: keySet.ed25519.data,
                bls: keySet.bls.data,
                metadata: Data128()
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

        return state
    }
    // TODO: add file genesis
    // public static func fileGenesis(config: ProtocolConfigRef) throws -> State
}
