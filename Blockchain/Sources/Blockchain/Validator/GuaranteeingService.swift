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

struct GuaranteeingAuthorizationFunction: IsAuthorizedFunction {}
struct GuaranteeingRefineInvocation: RefineInvocation {}

public final class GuaranteeingService: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let runtime: Runtime
    private let extrinsicPool: ExtrinsicPoolService
    private let workPackagePool: WorkPackagePoolService
    private let guarantees: ThreadSafeContainer<[RuntimeEvents.GuaranteeGenerated]> = .init([])
    private let authorizationFunction: GuaranteeingAuthorizationFunction
    private let dataAvailability: DataAvailability
    private let refineInvocation: GuaranteeingRefineInvocation

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
        authorizationFunction = GuaranteeingAuthorizationFunction()
        refineInvocation = GuaranteeingRefineInvocation()
        workPackagePool = await WorkPackagePoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)
        dataAvailability = await DataAvailability(
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
        // TODO: find out current coreIndex
        let coreIndex = CoreIndex(0)

        let workPackages = await workPackagePool.getWorkPackage()
        for workPackage in workPackages.array {
            if try validate(workPackage: workPackage.workPackage) {
                let workReport = try await createWorkReport(for: workPackage.workPackage, coreIndex: coreIndex)
                logger.info("workReport: \(workReport)")
                // TODO: eventbus publish workReport
                // eventBus.publish()
            } else {
                logger.error("WorkPackage validation failed")
            }
        }
    }

    // workpackage from l2 p2p server
    // workpackage -> workresult -> workreport
    private func createWorkReport(for workPackage: WorkPackage, coreIndex: CoreIndex) async throws -> WorkReport {
        // TODO: B.3. Refine Invocation
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let packageHash = workPackage.hash()
        // TODO: add authorizerHash
        let authorizerHash = Data32()
        // TODO: add authorizationOutput
        let authorizationOutput = Data()
        var exportSegmentOffset: UInt64 = 0
        // IsAuthorizedFunction invoke
        let res = try await authorizationFunction.invoke(config: config, package: workPackage, coreIndex: coreIndex)
        switch res {
        case let .success(data):
            var workResults = [WorkResult]()
            for item in workPackage.workItems {
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
                // the import segments and extrinsic data blobs as dictated by the work-item ?
                // from off-chain preimage ?
                // Extrinsic data are blobs generally by the work-package builder.
                let extrinsicDataBlobs = [Data]()
                // TODO: fix exportSegments func
                try await dataAvailability.exportSegments(data: importSegments)
                // RefineInvocation invoke up data to workresult
                let refineRes = try await refineInvocation
                    .invoke(
                        config: config,
                        serviceAccounts: state.value,
                        codeHash: workPackage.authorizationCodeHash,
                        gas: item.refineGasLimit,
                        service: item.serviceIndex,
                        workPackageHash: packageHash,
                        workPayload: item.payloadBlob,
                        refinementCtx: workPackage.context,
                        authorizerHash: authorizerHash,
                        authorizationOutput: authorizationOutput,
                        importSegments: importSegments,
                        extrinsicDataBlobs: extrinsicDataBlobs,
                        exportSegmentOffset: exportSegmentOffset
                    )
                // Export -> DA ？ or exportSegmentOffset + outputDataSegmentsCount ？
                exportSegmentOffset += UInt64(item.outputDataSegmentsCount)
                logger.info("Refined work package: \(refineRes)")
                let workResult = WorkResult(
                    serviceIndex: item.serviceIndex,
                    codeHash: workPackage.authorizationCodeHash,
                    payloadHash: Data32(), // TODO: generate payloadHash
                    gas: item.refineGasLimit,
                    output: WorkOutput(refineRes.result)
                )
                workResults.append(workResult)
            }
            // TODO: generate or find AvailabilitySpecifications
            let packageSpecification = AvailabilitySpecifications.dummy(config: config)
            return try WorkReport(
                authorizerHash: authorizerHash,
                coreIndex: coreIndex,
                authorizationOutput: authorizationOutput,
                refinementContext: workPackage.context,
                packageSpecification: packageSpecification,
                lookup: [:], // TODO: find out lookup
                results: ConfigLimitedSizeArray(config: config, array: workResults)
            )

        case let .failure(error):
            logger.error("Authorization failed with error: \(error)")
            throw error
        }
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
