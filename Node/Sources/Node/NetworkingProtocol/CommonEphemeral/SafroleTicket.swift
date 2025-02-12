import Blockchain

public struct SafroleTicketMessage: Codable, Sendable, Equatable, Hashable {
    public var epochIndex: EpochIndex
    public var attempt: TicketIndex
    public var proof: BandersnatchRingVRFProof
}
