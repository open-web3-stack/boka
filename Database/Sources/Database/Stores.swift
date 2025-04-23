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
    // block indexes
    // 0x00 + timeslot => Set<BlockHash>
    // 0x01 + blockNumber => Set<BlockHash>
    // 0x02 + blockHash => blockNumber
    // 0x03 + blockHash => stateRootHash
    case blockIndexes = 2
    // state trie
    // 0x00 + hash => trie node
    // 0x01 + value hash => state value
    case state = 3
    // ref count
    // 0x00 + node hash => ref count
    // 0x01 + value hash => ref count
    case stateRefs = 4
    // guaranteedWorkReports
    // workReportHash => guaranteedWorkReport
    case guaranteedWorkReports = 5
}

enum MetaKey: UInt8 {
    case genesisHash = 0 // Data32
    case heads = 1 // Set<Data32>
    case finalizedHead = 2 // Data32

    var key: Data {
        Data([rawValue])
    }
}
