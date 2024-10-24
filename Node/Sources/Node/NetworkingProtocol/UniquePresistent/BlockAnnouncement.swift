import Blockchain
import Utils

public struct HashAndSlot: Codable, Sendable, Hashable {
    public var hash: Data32
    public var timeslot: TimeslotIndex
}

public struct BlockAnnouncementHandshake: Codable, Sendable {
    public var finalized: HashAndSlot
    public var heads: [HashAndSlot]
}

public struct BlockAnnouncement: Codable, Sendable {
    public var header: Header
    public var finalized: HashAndSlot
}
