import Foundation
import Synchronization
import TracingUtils
import Utils

public enum GuaranteeingServiceError: Error {
    case noAuthorizerHash
    case invalidExports
}

public final class GuaranteeingService: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let keystore: KeyStore
    private let dataAvailability: DataAvailability

    private let authorizationFunction: IsAuthorizedFunction
    private let refineFunction: RefineFunction

    let signingKey: ThreadSafeContainer<(ValidatorIndex, Ed25519.SecretKey)?> = .init(nil)

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        keystore: KeyStore,
        dataStore: DataStore
    ) async {
        self.dataProvider = dataProvider
        self.keystore = keystore
        dataAvailability = await DataAvailability(
            config: config,
            eventBus: eventBus,
            scheduler: scheduler,
            dataProvider: dataProvider,
            dataStore: dataStore
        )

        authorizationFunction = VMFunctions.shared
        refineFunction = VMFunctions.shared

        super.init(id: "GuaranteeingService", config: config, eventBus: eventBus, scheduler: scheduler)

        await subscribe(RuntimeEvents.WorkPackagesReceived.self, id: "GuaranteeingService.WorkPackagesReceived") { [weak self] event in
            try await self?.on(workPackagesReceived: event)
        }
    }

    public func onSyncCompleted() async {
        let nowTimeslot = timeProvider.getTime().timeToTimeslot(config: config)
        let epoch = nowTimeslot.timeslotToEpochIndex(config: config)
        await onBeforeEpoch(epoch: epoch)

        scheduleForNextEpoch("GuaranteeingService.scheduleForNextEpoch") { [weak self] epoch in
            await self?.onBeforeEpoch(epoch: epoch)
        }
    }

    private func onBeforeEpoch(epoch: EpochIndex) async {
        await withSpan("GuaranteeingService.onBeforeEpoch", logger: logger) { _ in
            let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
            let timeslot = epoch.epochToTimeslotIndex(config: config)
            // simulate next block to determine the correct current validators
            // this is more accurate than just using nextValidators from current state
            let res = try state.value.updateSafrole(
                config: config,
                slot: timeslot,
                entropy: Data32(),
                offenders: [],
                extrinsics: .dummy(config: config)
            )
            let validators = res.state.currentValidators

            let keys = await keystore.getAll(Ed25519.self)
            var result: (ValidatorIndex, Ed25519.SecretKey)?
            for key in keys {
                if let idx = validators.array.firstIndex(where: { $0.ed25519 == key.publicKey.data }) {
                    result = (ValidatorIndex(idx), key)
                    break
                }
            }

            signingKey.value = result
        }
    }

    private func on(workPackagesReceived event: RuntimeEvents.WorkPackagesReceived) async throws {
        try await refine(package: event.item)
    }

    private func refine(package: WorkPackageRef) async throws {
        guard let (validatorIndex, signingKey) = signingKey.value else {
            logger.debug("not in current validator set, skipping refine")
            return
        }

        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        // TODO: check for edge cases such as epoch end
        let currentCoreAssignment = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: state.value.timeslot + 1
        )
        guard let coreIndex = currentCoreAssignment[safe: Int(validatorIndex)] else {
            try throwUnreachable("invalid validator index/core assignment")
        }

        let workReport = try await createWorkReport(for: package, coreIndex: coreIndex)
        let payload = SigningContext.guarantee + workReport.hash().data
        let signature = try signingKey.sign(message: payload)
        let event = RuntimeEvents.WorkReportGenerated(item: workReport, signature: signature)
        publish(event)
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
                // RefineFunction invoke up data to workresult
                let refineRes = try await refineFunction
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
}
