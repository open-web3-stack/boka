extension RuntimeEvents.BlockImported {
    public func isNewEpoch(config: ProtocolConfigRef) -> Bool {
        let epochLength = UInt32(config.value.epochLength)
        let prevEpoch = parentState.value.timeslot / epochLength
        let newEpoch = state.value.timeslot / epochLength
        return prevEpoch != newEpoch
    }
}
