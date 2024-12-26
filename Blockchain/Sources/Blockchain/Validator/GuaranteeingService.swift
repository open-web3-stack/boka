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
//        let nowTimeslot = timeProvider.getTime().timeToTimeslot(config: config)
//        let epoch = nowTimeslot.timeslotToEpochIndex(config: config)
        await onGuaranteeing()
    }

    public func onSyncCompleted() async {
        scheduleForNextEpoch("GuaranteeingService.scheduleForNextEpoch") { [weak self] _ in
            await self?.onGuaranteeing()
        }
    }

    public func scheduleGuaranteeTasks() async throws {
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        // The most recent block’s τimeslot.
        let timeslot = state.value.timeslot
        let coreAssignmentRotationPeriod = UInt32(config.value.coreAssignmentRotationPeriod)
        let currentCoreAssignment = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: timeslot
        )
        let ed25519PublicKeys = state.value.currentValidators.map(\.ed25519)

        let nowTimeslot = timeProvider.getTime().timeToTimeslot(config: config)
        // TODO: find out the core on which it should be executed
        let coreIndex = CoreIndex(0)

        let workPackages = await workPackagePool.getWorkPackage()
        for workPackage in workPackages.array {
            if try validate(workPackage: workPackage.workPackage) {
                let workReport = try await createWorkReport(for: workPackage.workPackage, coreIndex: coreIndex)
                logger.info("workReport: \(workReport)")
                let addEvent = RuntimeEvents.WorkReportGenerated(items: [workReport])
                publish(addEvent)
            } else {
                logger.error("WorkPackage validation failed")
            }
        }
    }

    // workpackage from l2 p2p server
    // workpackage -> workresult -> workreport
    private func createWorkReport(for workPackage: WorkPackage, coreIndex: CoreIndex) async throws -> WorkReport {
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let packageHash = workPackage.hash()
        // We define the work-package’s implied authorizer as pa,
        // the hash of the concatenation of the authorization code and the parameterization.
        // We define the authorization code as pc and require that it be available at the time
        // of the lookup anchor block from the historical lookup of service ph
        // The historical lookup function, Λ, is defined in equation 9.7.
        // TODO: add authorizerHash
        let authorizerHash = Data32()
        // TODO: add authorizationOutput
        var exportSegmentOffset: UInt64 = 0
        // B.2. Is-Authorized Invocation
        let res = try await authorizationFunction.invoke(config: config, package: workPackage, coreIndex: coreIndex)
        switch res {
        // authorizationFunction -> authorizationOutput
        case let .success(authorizationOutput):
            var workResults = [WorkResult]()
            for item in workPackage.workItems {
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
                // Export -> DA or exportSegmentOffset + outputDataSegmentsCount ？
                exportSegmentOffset += UInt64(item.outputDataSegmentsCount)
                logger.info("Refined work package: \(refineRes)")
                // TODO: generate payloadHash the hash of the payload (l) within the work item
                // which was executed in the refine stage to give this result.
                // Computation of Work Results
                let workResult = WorkResult(
                    serviceIndex: item.serviceIndex,
                    codeHash: workPackage.authorizationCodeHash,
                    payloadHash: Data32(),
                    gas: item.refineGasLimit,
                    output: WorkOutput(refineRes.result)
                )
                workResults.append(workResult)
            }
            // TODO: generate or find AvailabilitySpecifications
            let packageSpecification = AvailabilitySpecifications(
                workPackageHash: packageHash,
                length: 0, // xx
                erasureRoot: Data32(),
                segmentRoot: Data32(),
                segmentCount: UInt16(exportSegmentOffset)
            )

            var oldLookups = [Data32: Data32]()
            for item in state.value.recentHistory.items {
                oldLookups.merge(item.lookup, uniquingKeysWith: { _, new in new })
            }
            return try WorkReport(
                authorizerHash: authorizerHash,
                coreIndex: coreIndex,
                authorizationOutput: authorizationOutput,
                refinementContext: workPackage.context,
                packageSpecification: packageSpecification,
                lookup: oldLookups,
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

    private func onGuaranteeing() async {
        await withSpan("GuaranteeingService.onBeforeEpoch", logger: logger) { _ in
            try await scheduleGuaranteeTasks()
        }
    }

    private func onGuaranteeGenerated(event: RuntimeEvents.GuaranteeGenerated) async throws {
        guarantees.write { $0.append(event) }
    }
}
