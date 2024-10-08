import Foundation
import TracingUtils
import Utils

// find out when and which core we are guaranteeing for and schedule a task for it
// get work package from the pool
// try to guarantee the work package
// if successful, create a work report and publish it
// chunk the work package and exported data
// publish the chunks
public final class GuaranteeingService: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let runtime: Runtime
    private let extrinsicPool: ExtrinsicPoolService

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        keystore: KeyStore,
        runtime: Runtime,
        extrinsicPool: ExtrinsicPoolService
    ) async {
        self.dataProvider = dataProvider
        self.keystore = keystore
        self.runtime = runtime
        self.extrinsicPool = extrinsicPool

        super.init(logger: Logger(label: "BlockAuthor"), config: config, eventBus: eventBus, scheduler: scheduler)
    }

    public func on(genesis _: StateRef) async {}
}
