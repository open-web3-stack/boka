import Foundation
import Synchronization
import TracingUtils
import Utils

public enum GuaranteeingServiceError: Error {
    case invalidValidatorIndex
    case customValidatorNotFound
    case noAuthorizerHash
    case invalidCoreIndex
    case invalidExports
}

struct GuaranteeingAuthorizationFunction: IsAuthorizedFunction {}
struct GuaranteeingRefineInvocation: RefineInvocation {}

public final class GuaranteeingService: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let runtime: Runtime
    private let safroleTicketPool: SafroleTicketPoolService
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
        safroleTicketPool: SafroleTicketPoolService,
        dataStore: DataStore
    ) async {
        self.dataProvider = dataProvider
        self.keystore = keystore
        self.runtime = runtime
        self.safroleTicketPool = safroleTicketPool
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
        await onGuaranteeing()
    }

    public func scheduleGuaranteeTasks() async throws {
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let header = try await dataProvider.getHeader(hash: dataProvider.bestHead.hash)
        let authorIndex = header.value.authorIndex
        let authorKey = try Ed25519.PublicKey(from: state.value.currentValidators[Int(authorIndex)].ed25519)
        let key = await keystore.get(Ed25519.self, publicKey: authorKey)
        if key == nil {
            throw GuaranteeingServiceError.customValidatorNotFound
        }
        let currentCoreAssignment = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: state.value.timeslot
        )
        guard authorIndex < ValidatorIndex(currentCoreAssignment.count) else {
            logger.error("AuthorIndex not found")
            throw GuaranteeingServiceError.invalidValidatorIndex
        }
        let coreIndex = currentCoreAssignment[Int(authorIndex)]
        guard coreIndex < CoreIndex(config.value.totalNumberOfCores) else {
            throw GuaranteeingServiceError.invalidCoreIndex
        }

        let workPackages = await workPackagePool.getPendingPackages()
        for workPackage in workPackages {
            if try validate(workPackage: workPackage) {
                let workReport = try await createWorkReport(for: workPackage, coreIndex: coreIndex)
                let event = RuntimeEvents.WorkReportGenerated(items: [workReport])
                publish(event)
                break
            } else {
                logger.error("WorkPackage validation failed")
            }
        }
    }

    // workpackage -> workresult -> workreport
    private func createWorkReport(for workPackage: WorkPackageRef, coreIndex: CoreIndex) async throws -> WorkReport {
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let packageHash = workPackage.hash
        let corePool = state.value.coreAuthorizationPool[coreIndex]
        let authorizerHash = try corePool.array.first.unwrap(orError: GuaranteeingServiceError.noAuthorizerHash)
        var exportSegmentOffset: UInt16 = 0
        // B.2. the authorization output, the result of the Is-Authorized function
        // TODO: waiting for authorizationFunction done  Mock a result
        // let res = try await authorizationFunction.invoke(config: config, serviceAccounts: state.value, package: workPackage, coreIndex:
        // coreIndex)
        let res = Result<Data, WorkResultError>.success(Data())
        switch res {
        // authorizationFunction -> authorizationOutput
        case let .success(authorizationOutput):
            var workResults = [WorkResult]()

            var exportSegments = [Data4104]()

            // TODO: make this lazy, only fetch when needed by PVM
            var importSegments = [[Data4104]]()
            for item in workPackage.value.workItems {
                try await importSegments.append(dataAvailability.fetchSegment(segments: item.inputs))
            }

            for (i, item) in workPackage.value.workItems.enumerated() {
                // TODO: generated by the work-package builder.
                let extrinsicDataBlobs = [Data]()

                // RefineInvocation invoke up data to workresult
                let refineRes = try await refineInvocation
                    .invoke(
                        config: config,
                        serviceAccounts: state.value,
                        workItemIndex: i,
                        workPackage: workPackage.value,
                        authorizerOutput: authorizationOutput,
                        importSegments: importSegments,
                        exportSegmentOffset: UInt64(exportSegmentOffset)
                    )
                // Export -> DA or exportSegmentOffset + outputDataSegmentsCount ？
                exportSegmentOffset += item.outputDataSegmentsCount
                let workResult = WorkResult(
                    serviceIndex: item.serviceIndex,
                    codeHash: workPackage.value.authorizationCodeHash,
                    payloadHash: item.payloadBlob.blake2b256hash(),
                    gas: item.refineGasLimit,
                    output: WorkOutput(refineRes.result)
                )
                workResults.append(workResult)

                guard item.outputDataSegmentsCount == refineRes.exports.count else {
                    throw GuaranteeingServiceError.invalidExports
                }

                exportSegments.append(contentsOf: refineRes.exports)
            }

            let (erasureRoot, length) = try await dataAvailability.exportWorkpackageBundle(bundle: WorkPackageBundle(
                workPackage: workPackage.value,
                extrinsic: [], // TODO: get extrinsic data
                importSegments: [],
                justifications: []
            ))

            let segmentRoot = try await dataAvailability.exportSegments(data: exportSegments, erasureRoot: erasureRoot)

            // TODO: generate or find AvailabilitySpecifications  14.4.1 work-package bundle
            let packageSpecification = AvailabilitySpecifications(
                workPackageHash: packageHash,
                length: length,
                erasureRoot: erasureRoot,
                segmentRoot: segmentRoot,
                segmentCount: exportSegmentOffset
            )
            // The historical lookup function, Λ, is defined in equation 9.7.
            var oldLookups = [Data32: Data32]()
            for item in state.value.recentHistory.items {
                oldLookups.merge(item.lookup, uniquingKeysWith: { _, new in new })
            }
            return try WorkReport(
                authorizerHash: authorizerHash,
                coreIndex: coreIndex,
                authorizationOutput: authorizationOutput,
                refinementContext: workPackage.value.context,
                packageSpecification: packageSpecification,
                lookup: oldLookups,
                results: ConfigLimitedSizeArray(config: config, array: workResults)
            )

        case let .failure(error):
            logger.error("Authorization failed with error: \(error)")
            throw error
        }
    }

    private func validate(workPackage _: WorkPackageRef) throws -> Bool {
        // TODO: Add validate func
        true
    }

    private func onGuaranteeing() async {
        await withSpan("GuaranteeingService.onGuaranteeing", logger: logger) { _ in
            try await scheduleGuaranteeTasks()
        }
    }

    private func onGuaranteeGenerated(event: RuntimeEvents.GuaranteeGenerated) async throws {
        guarantees.write { $0.append(event) }
    }
}
