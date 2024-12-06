import Blockchain
import Foundation
import RocksDBSwift
import Utils

enum StoreId: UInt8, ColumnFamilyKey {
    // metadata and configurations
    case meta = 0
    // blocks
    // blockHash => blockBody
    case blocks = 1
    // timeslot => blockHash
    // blockNumber => blockHash
    case blockIndexes = 2
    // state trie
    // hash => trie node
    // value hash => state value
    case state = 3
    // ref count
    // node hash => ref count
    // value hash => ref count
    case stateRefs = 4
}

enum MetaKey: UInt8 {
    case genesisHash = 0 // Data32
    case heads = 1 // Set<Data32>
    case finalizedHead = 2 // Data32

    var key: Data {
        Data([rawValue])
    }
}
