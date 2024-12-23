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
struct DefaultAuthorizationFunction: IsAuthorizedFunction {}

public final class GuaranteeingService: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let runtime: Runtime
    private let extrinsicPool: ExtrinsicPoolService
    private let workPackagePool: WorkPackagePoolService
    private let guarantees: ThreadSafeContainer<[RuntimeEvents.GuaranteeGenerated]> = .init([])
    // add DefaultAuthorizationFunction
    private let authorizationFunction: DefaultAuthorizationFunction
    private let daataAvailability: DataAvailability

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        keystore: KeyStore,
        runtime: Runtime,
        extrinsicPool: ExtrinsicPoolService,
        dataStore: DataStore
    ) async {
        self.dataProvider = dataProvider
        self.keystore = keystore
        self.runtime = runtime
        self.extrinsicPool = extrinsicPool
        authorizationFunction = DefaultAuthorizationFunction()
        workPackagePool = await WorkPackagePoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)
        daataAvailability = await DataAvailability(
            config: config,
            eventBus: eventBus,
            scheduler: scheduler,
            dataProvider: dataProvider,
            dataStore: dataStore
        )
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

    public func scheduleGuaranteeTasks() async throws {
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        // The most recent block’s τimeslot.
        let timeslot = state.value.timeslot
        let coreAssignmentRotationPeriod = UInt32(config.value.coreAssignmentRotationPeriod)
        let nowTimeslot = timeProvider.getTime().timeToTimeslot(config: config)
        // bool isCurrent
        let isCurrent = (nowTimeslot / coreAssignmentRotationPeriod) == (timeslot / coreAssignmentRotationPeriod)
        // coreAuthorizationPool
        var pool = state.value.coreAuthorizationPool
        for coreIndex in 0 ..< pool.count {
            var corePool = pool[coreIndex]
            logger.info("corePool: \(corePool)")
        }

        let workPackages = await workPackagePool.getWorkPackage()
        for workPackage in workPackages.array {
            if try validate(workPackage: workPackage.workPackage) {
                let workReport = try await createWorkReport(for: workPackage.workPackage)
                logger.info("workReport: \(workReport)")
            } else {
                logger.error("WorkPackage validation failed")
            }
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

    // workpackage from l2 p2p server
    // workpackage -> workresult -> workreport
    private func createWorkReport(for workPackage: WorkPackage) async throws -> WorkReport {
        // TODO: B.3. Refine Invocation
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let packageHash = workPackage.hash()
        // TODO: find out service account & add it
        var serviceAccounts = [ServiceIndex: ServiceAccount]()
        // TODO: add current coreIndex
        let coreIndex = CoreIndex(0)
        // IsAuthorizedFunction invoke
        let res = try await authorizationFunction.invoke(config: config, package: workPackage, coreIndex: coreIndex)
        switch res {
        case let .success(data):
            for item in workPackage.workItems {
                let gas = item.refineGasLimit
                let serviceIndex = item.serviceIndex
                let workPackageHash = packageHash
                let workPayload = item.payloadBlob
                let refinementCtx = workPackage.context
                let authorizerHash = workPackage.authorizationCodeHash
                let authorizationOutput = data
                // 14.2.1. Segments, Imports and Exports. Imports DA
                var importSegments = [Data]()
                for importSegment in item.inputs {
                    switch importSegment.root {
                    case let .segmentRoot(data):
                        importSegments.append(data.data)
                    case let .workPackageHash(data):
                        importSegments.append(data.data)
                    }
                }
                // TODO: exportSegments
                try await daataAvailability.exportSegments(data: importSegments)
                // from off-chain preimage
                let extrinsicDataBlobs: [Data] = []
                // TODO: 14.3.1. Exporting.
                let exportSegmentOffset: UInt64 = 0 // Export -> DA
                // RefineInvocation invoke up data to workresult
                logger.info("gas: \(gas)")
                logger.info("serviceIndex: \(serviceIndex)")
                logger.info("workPackageHash: \(workPackageHash)")
                logger.info("workPayload: \(workPayload)")
                logger.info("refinementCtx: \(refinementCtx)")
                logger.info("authorizerHash: \(authorizerHash)")
                logger.info("authorizationOutput: \(authorizationOutput)")
                logger.info("importSegments: \(importSegments)")
                logger.info("extrinsicDataBlobs: \(extrinsicDataBlobs)")
                logger.info("exportSegmentOffset: \(exportSegmentOffset)")
                logger.info("workPackage: \(workPackage)")
                logger.info("newServiceAccounts: \(serviceAccounts.count)")
            }
        case let .failure(error):
            logger.error("Authorization failed with error: \(error)")
        }

        return WorkReport.dummy(config: config)
    }

    private func validate(workPackage _: WorkPackage) throws -> Bool {
        // TODO: Add validate func
        true
    }

    private func onGuaranteeingEpoch(epoch: EpochIndex) async {
        logger.debug("Processing guarantees for epoch \(epoch)")
        await withSpan("GuaranteeingService.onBeforeEpoch", logger: logger) { _ in
            guarantees.value = []
            try await scheduleGuaranteeTasks()
        }
    }

    private func onGuaranteeGenerated(event: RuntimeEvents.GuaranteeGenerated) async throws {
        guarantees.write { $0.append(event) }
    }
}
