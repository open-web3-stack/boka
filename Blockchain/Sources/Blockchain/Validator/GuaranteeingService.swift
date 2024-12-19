import Foundation
import Synchronization
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
    private let workPackagePool: WorkPackagePoolService
    private let guarantees: ThreadSafeContainer<[RuntimeEvents.GuaranteeGenerated]> = .init([])

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
        workPackagePool = await WorkPackagePoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)
        super.init(id: "GuaranteeingService", config: config, eventBus: eventBus, scheduler: scheduler)

        await subscribe(RuntimeEvents.GuaranteeGenerated.self, id: "GuaranteeingService.GuaranteeGenerated") { [weak self] event in
            try await self?.onGuaranteeGenerated(event: event)
        }
    }

    public func on(genesis _: StateRef) async {
        let nowTimeslot = timeProvider.getTime().timeToTimeslot(config: config)
        let epoch = nowTimeslot.timeslotToEpochIndex(config: config)
        await onGuaranteeingEpoch(epoch: epoch)
    }

    public func onSyncCompleted() async {
        scheduleForNextEpoch("GuaranteeingService.scheduleForNextEpoch") { [weak self] epoch in
            await self?.onGuaranteeingEpoch(epoch: epoch)
        }
    }

    public func scheduleGuaranteeTasks(epoch _: EpochIndex) async throws {
        // let timeslot = epoch.epochToTimeslotIndex(config: config)
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        // The most recent block’s τimeslot.
        let timeslot = state.value.timeslot
        let currentCoreAssignment = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: timeslot
        )
        let coreCount = currentCoreAssignment.count
        for coreIndex in 0 ..< coreCount {
            let core = currentCoreAssignment[coreIndex]
            let workPackages = await workPackagePool.getWorkPackage(for: core)
            for workPackage in workPackages.array {
                let validateWP = try validateWorkPackage(workPackage.workPackage)
                if validateWP {
                    let workReport = try await createWorkReport(for: workPackage.workPackage, core: core)
                    // sign work report
                    // eventbus
                } else {
                    logger.error("WorkPackage validation failed")
                }
            }

            //
        }
    }

//    public protocol RefineInvocation {
//        func invoke(
//            config: ProtocolConfigRef,
//            serviceAccounts: some ServiceAccounts,
//            codeHash: Data,
//            gas: Gas,
//            service: ServiceIndex,
//            workPackageHash: Data32,
//            workPayload: Data,
//            refinementCtx: RefinementContext,
//            authorizerHash: Data32,
//            authorizationOutput: Data,
//            importSegments: [Data], // array of Data4104
//            extrinsicDataBlobs: [Data],
//            exportSegmentOffset: UInt64
//        ) async throws -> (result: Result<Data, WorkResultError>, exports: [Data])
//    }

    private func createWorkReport(for workPackage: WorkPackage, core _: CoreIndex) async throws -> WorkReport {
        // TODO:
        // RefineInvocation ouput
        // outdata -> workreport struct
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        var gas = Gas(0)
//        var ServiceAccountDetails = try await state.value.get(serviceAccount: workPackage.authorizationServiceIndex)
        // how to get service accounts
        var serviceAccounts = state.value.serviceAccount
        var newServiceAccounts = [ServiceIndex: ServiceAccount]()
        var ServiceIndex = workPackage.authorizationServiceIndex
        let workPackageHash = workPackage.hash() // workPackage hash
        let workPayload = workPackage.payload() // workpackage payload
        let refinementCtx = workPackage.context
        let authorizerHash = workPackage.authorizationCodeHash
        let authorizationOutput = Data()
        let importSegments: [Data] = []
        let extrinsicDataBlobs: [Data] = []
        let exportSegmentOffset: UInt64 = 0
        return WorkReport.dummy(config: config)
    }

    private func validateWorkPackage(_: WorkPackage) throws -> Bool {
        // Add validate func
        true
    }

    private func onGuaranteeingEpoch(epoch: EpochIndex) async {
        logger.debug("Processing guarantees for epoch \(epoch)")
        await withSpan("GuaranteeingService.onBeforeEpoch", logger: logger) { _ in
            guarantees.value = []
            try await scheduleGuaranteeTasks(epoch: epoch)
        }
    }

    private func onGuaranteeGenerated(event: RuntimeEvents.GuaranteeGenerated) async throws {
        guarantees.write { $0.append(event) }
    }
}
