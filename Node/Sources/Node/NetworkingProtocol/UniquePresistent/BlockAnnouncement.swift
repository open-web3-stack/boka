import Blockchain
import Utils

public struct BlockAnnouncement: Codable, Sendable {
    public var header: Header
    public var headerHash: Data32
    public var timeslot: TimeslotIndex
}
