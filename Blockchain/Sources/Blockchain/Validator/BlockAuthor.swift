import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "BlockAuthor")

public class BlockAuthor: ServiceBase, @unchecked Sendable {
    private let blockchain: Blockchain
    private let keystore: KeyStore
    private let scheduler: Scheduler
    private let extrinsicPool: ExtrinsicPoolService

    public init(
        blockchain: Blockchain,
        eventBus: EventBus,
        keystore: KeyStore,
        scheduler: Scheduler,
        extrinsicPool: ExtrinsicPoolService
    ) async {
        self.blockchain = blockchain
        self.keystore = keystore
        self.scheduler = scheduler
        self.extrinsicPool = extrinsicPool

        super.init(blockchain.config, eventBus)
    }

    public func on(genesis _: StateRef) async {}
}
