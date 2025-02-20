import Foundation
import TracingUtils
import Utils

enum WorkPackageStatus {
    case pending
    // work report is generated and waiting for assursor to make it available
    case refined
    // work report is available and waiting for the work report to be accurmulated
    case assured
}

private struct WorkPackageInfo {
    let workPackage: WorkPackageRef
    var status: WorkPackageStatus
}

private actor WorkPackageStorage {
    var logger: Logger!
    var workPackages: [Data32: WorkPackageInfo] = [:]

    let ringContext: Bandersnatch.RingContext
    var verifier: Bandersnatch.Verifier!
    var entropy: Data32 = .init()
    init(ringContext: Bandersnatch.RingContext) {
        self.ringContext = ringContext
    }

    func setLogger(_ logger: Logger) {
        self.logger = logger
    }

    func add(packages: [WorkPackageRef], config: ProtocolConfigRef) {
        for package in packages {
            guard validatePackage(package, config: config) else {
                logger.warning("Invalid work package: \(package)")
                continue
            }
            workPackages[package.hash] = WorkPackageInfo(workPackage: package, status: .pending)
        }
    }

    private func validatePackage(_: WorkPackageRef, config _: ProtocolConfigRef) -> Bool {
        // TODO: add validate logic
        true
    }

    func packageRefined(packageHashes: [Data32]) {
        for hash in packageHashes {
            workPackages[hash]?.status = .refined
        }
    }

    func getPendingPackages() -> [WorkPackageRef] {
        workPackages.values.filter { $0.status == .pending }.map(\.workPackage)
    }
}

public struct SegmentsRootMapping: Codable {
    public let workPackageHash: Data32
    public let segmentsRoot: SegmentsRoot
}

public typealias SegmentsRoot = Data32
public typealias SegmentsRootMappings = [SegmentsRootMapping]

public struct Guarantor: Codable, Identifiable {
    public let id: Data32 // Unique identifier for the guarantor (e.g., public key hash)
    public let coreIndex: CoreIndex // The core index to which the guarantor is assigned

    // Method to receive a work package bundle
    public func receiveWorkPackageBundle(
        coreIndex _: CoreIndex,
        segmentsRootMappings: SegmentsRootMappings,
        bundle: WorkPackageBundle
    ) async throws -> (Data32, Data) {
        // 1. Perform basic verification
        guard try validateWorkPackageBundle(bundle, segmentsRootMappings: segmentsRootMappings) else {
            throw WorkPackageError.invalidBundle
        }

        // 2. Execute refine logic
        let workReportHash = try await refineWorkPackageBundle(bundle)

        // 3. Sign the work report hash
        let signature = try await signData(workReportHash)

        return (workReportHash, signature)
    }

    private func validateWorkPackageBundle(
        _ bundle: WorkPackageBundle,
        segmentsRootMappings: SegmentsRootMappings
    ) throws -> Bool {
        // 1. Validate the work package authorization
        guard try validateAuthorization(bundle.workPackage) else {
            return false
        }

        // 2. Validate the segments-root mappings
        for mapping in segmentsRootMappings {
            guard try validateSegmentsRootMapping(mapping, for: bundle.workPackage) else {
                return false
            }
        }

        return true
    }

    private func validateSegmentsRootMapping(
        _: SegmentsRootMapping,
        for _: WorkPackage
    ) throws -> Bool {
        // TODO: Implement logic to validate the segments-root mapping
        true // Placeholder
    }

    private func validateAuthorization(_: WorkPackage) throws -> Bool {
        // TODO: Implement logic to validate the work package authorization
        true // Placeholder
    }

    private func refineWorkPackageBundle(_: WorkPackageBundle) async throws -> Data32 {
        // TODO: Implement refine logic here
        // For example, execute the work items and generate a work report
//        let workReportHash = try await refineLogic.execute(bundle)
        Data32()
    }

    private func signData(_: Data32) async throws -> Data {
        // TODO: Implement signing logic here
        // For example, use the guarantor's private key to sign the data
//        let signature = try await keystore.sign(data: data, with: privateKey)
        Data()
    }
}

public final class WorkPackagePoolService: ServiceBase, @unchecked Sendable {
    private var storage: WorkPackageStorage
    private let dataProvider: BlockchainDataProvider

    public init(
        config: ProtocolConfigRef,
        dataProvider: BlockchainDataProvider,
        eventBus: EventBus
    ) async {
        self.dataProvider = dataProvider

        let ringContext = try! Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))
        storage = WorkPackageStorage(ringContext: ringContext)

        super.init(id: "WorkPackagePoolService", config: config, eventBus: eventBus)
        await storage.setLogger(logger)

        await subscribe(RuntimeEvents.WorkPackagesReceived.self, id: "WorkPackagePool.WorkPackagesReceived") { [weak self] event in
            try await self?.on(workPackagesReceived: event)
        }

        await subscribe(RuntimeEvents.WorkReportGenerated.self, id: "WorkPackagePool.WorkReportGenerated") { [weak self] event in
            try await self?.on(workPackagesGenerated: event)
        }

        // TODO: add remove subscribe
    }

    private func on(workPackagesReceived event: RuntimeEvents.WorkPackagesReceived) async throws {
        await storage.add(packages: event.items, config: config)
    }

    private func on(workPackagesGenerated event: RuntimeEvents.WorkReportGenerated) async throws {
        await storage.packageRefined(packageHashes: event.items.map(\.packageSpecification.workPackageHash))
    }

    public func addWorkPackages(packages: [WorkPackageRef]) async throws {
        await storage.add(packages: packages, config: config)
    }

    public func createWorkPackageBundle(_ workPackage: WorkPackage) async throws -> WorkPackageBundle {
        // 1. Retrieve the necessary data for the bundle
        let extrinsicData = try await retrieveExtrinsicData(for: workPackage)
        let importSegments = try await retrieveImportSegments(for: workPackage)
        let justifications = try await retrieveJustifications(for: workPackage)

        // 2. Construct the work package bundle
        return WorkPackageBundle(
            workPackage: workPackage,
            extrinsic: extrinsicData,
            importSegments: importSegments,
            justifications: justifications
        )
    }

//    public func retrieveSegmentsRootMappings(for workPackage: WorkPackage) async throws -> SegmentsRootMappings {
//        // 1. Get the import segments from the work package
//        let importSegments = try await retrieveImportSegments(for: workPackage)
//
//        // 2. Map work-package hashes to segments-roots
//        var mappings: SegmentsRootMappings = []
//        for segment in importSegments {
//            // 2.1. Get the work-package hash from the segment ??
//            let workPackageHash = workPackage.hash()
//
//            // 2.2. Retrieve the segments-root from the blockchain or data availability layer
//            let segmentsRoot = try await retrieveSegmentsRoot(for: workPackageHash)
//
//            // 2.3. Create a mapping and add it to the array
//            let mapping = SegmentsRootMapping(workPackageHash: workPackageHash, segmentsRoot: segmentsRoot)
//            mappings.append(mapping)
//        }
//
//        return mappings
//    }

//    private func retrieveSegmentsRoot(for workPackageHash: Data32) async throws -> SegmentsRoot {
//        // 1. Query the blockchain or data availability layer to get the segments-root
//        // For example, use a blockchain data provider to fetch the segments-root
//        let segmentsRoot = try await dataProvider.getSegmentsRoot(for: workPackageHash)
//
//        // 2. If the segments-root is not found, throw an error
//        guard let segmentsRoot = segmentsRoot else {
//            throw WorkPackageError.segmentsRootNotFound
//        }
//
//        return segmentsRoot
//    }

    public func shareWorkPackage(_ workPackage: WorkPackage, coreIndex: CoreIndex) async throws {
        // 1. Get other guarantors assigned to the same core
        let guarantors = try await getGuarantors(for: coreIndex)

        // 2. Validate the work package
        guard try validate(workPackage: workPackage) else {
            logger.error("Invalid work package: \(workPackage)")
            throw WorkPackageError.invalidWorkPackage
        }
        // 3. Create WorkPackageBundle

        let bundle = try await createWorkPackageBundle(workPackage)

        // 4. Send the bundle to other guarantors
        // 5. Map work-package hashes to segments-roots
        var mappings: SegmentsRootMappings = []
        for guarantor in guarantors {
            let (workReportHash, signature) = try await guarantor.receiveWorkPackageBundle(
                coreIndex: coreIndex,
                segmentsRootMappings: mappings,
                bundle: bundle
            )

            // 6. Publish the work report hash and signature
//            let event = RuntimeEvents.WorkReportGenerated(hash: workReportHash, signature: signature)
//            publish(event)
        }
    }

    public func getGuarantors(for coreIndex: CoreIndex) async throws -> [Guarantor] {
        // 1. Get the current blockchain state
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

        // 2. Get the core assignment for the current timeslot
        let coreAssignment: [CoreIndex] = state.value.getCoreAssignment(
            config: config,
            randomness: state.value.entropyPool.t2,
            timeslot: state.value.timeslot
        )

        // 3. Ensure the core index is valid
        guard coreIndex < coreAssignment.count else {
            logger.error("Invalid core index: \(coreIndex)")
            throw GuaranteeingServiceError.invalidValidatorIndex
        }

        // 4. Get the validator index assigned to the core
        let validatorIndex = coreAssignment[Int(coreIndex)]

        let validator = state.value.currentValidators[Int(validatorIndex)]
//        state.value.currentValidators[Int(authorIndex)].ed25519
        // 5. Create a Guarantor object for the validator
        let guarantor = Guarantor(
            id: validator.ed25519.blake2b256hash(), // Use the validator's public key hash as the ID
            coreIndex: coreIndex
        )

        return [guarantor]
    }

    private func retrieveExtrinsicData(for _: WorkPackage) async throws -> [Data] {
        // TODO: Implement retrieveExtrinsicData
        // Implement logic to retrieve extrinsic data associated with the work package
        // For example, fetch from the blockchain or local storage
        [] // Placeholder
    }

    private func retrieveImportSegments(for _: WorkPackage) async throws -> [Data4104] {
        // TODO: Implement retrieveImportSegments
        // Implement logic to retrieve imported data segments
        // For example, fetch from the data availability layer
        [] // Placeholder
    }

    private func retrieveJustifications(for _: WorkPackage) async throws -> [Data] {
        // TODO: Implement retrieveJustifications
        // Implement logic to retrieve justifications for the imported segments
        // For example, fetch proofs from the data availability layer
        [] // Placeholder
    }

    private func validate(workPackage _: WorkPackage) throws -> Bool {
        // TODO: Add validate func
        true
    }

    public func getPendingPackages() async -> [WorkPackageRef] {
        await storage.getPendingPackages()
    }
}
