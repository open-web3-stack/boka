import Foundation
import TracingUtils
import Utils

/// Holds the state of the blockchain.
/// Includes the canonical chain as well as pending forks.
/// Assume all blocks and states are valid and have been validated.
public class Blockchain {
    public let config: ProtocolConfigRef

    private let dataProvider: BlockchainDataProvider

    public init(config: ProtocolConfigRef, dataProvider: BlockchainDataProvider) async {
        self.config = config
        self.dataProvider = dataProvider
    }

    public func importBlock(_ block: BlockRef) async throws {
        try await withSpan("importBlock") { span in
            span.attributes["hash"] = block.hash.description

            let runtime = Runtime(config: config)
            let parent = try await dataProvider.getState(hash: block.header.parentHash)
            let state = try runtime.apply(block: block, state: parent)
            try await dataProvider.add(state: state)
        }
    }

    public func finalize(hash: Data32) async throws {
        // TODO: purge forks
        try await dataProvider.setFinalizedHead(hash: hash)
    }
}
