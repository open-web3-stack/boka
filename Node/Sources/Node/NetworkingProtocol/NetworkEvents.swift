import Blockchain
import Utils

public enum NetworkEvents {
    public struct PeerAdded: Event {
        public let info: PeerInfo
    }

    public struct PeerUpdated: Event {
        public let info: PeerInfo
        public let newBlockHeader: HeaderRef
    }

    public struct BulkSyncCompleted: Event {}
}
