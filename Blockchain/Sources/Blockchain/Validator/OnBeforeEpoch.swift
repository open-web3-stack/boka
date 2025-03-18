protocol OnBeforeEpoch {
    func onBeforeEpoch(epoch: EpochIndex, safroleState: SafrolePostState) async
}
