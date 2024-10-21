import Blockchain

public struct SafroleTicketMessage: Codable, Sendable {
    public var epochIndex: EpochIndex
    public var attempt: TicketIndex
    public var proof: BandersnatchRingVRFProof
}
