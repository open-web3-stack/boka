import Blockchain
import Utils

public struct HashAndSlot: Codable, Sendable, Hashable, Equatable {
    public var hash: Data32
    public var timeslot: TimeslotIndex
}

public struct BlockAnnouncementHandshake: Codable, Sendable, Hashable, Equatable {
    public var finalized: HashAndSlot
    public var heads: [HashAndSlot]
}

public struct BlockAnnouncement: Codable, Sendable, Hashable, Equatable {
    public var header: HeaderRef
    public var finalized: HashAndSlot
}
