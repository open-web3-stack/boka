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

    func update(state _: StateRef, config _: ProtocolConfigRef) throws {}

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

        await subscribe(RuntimeEvents.WorkReportGenerated.self, id: "WorkPackagePool.WorkPackagesReceived") { [weak self] event in
            try await self?.on(workPackagesGenerated: event)
        }

        // TODO: add remove subscribe
    }

    private func on(workPackagesReceived event: RuntimeEvents.WorkPackagesReceived) async throws {
        await storage.add(packages: event.items, config: config)
    }

    public func update(state: StateRef, config: ProtocolConfigRef) async throws {
        try await storage.update(state: state, config: config)
    }

    private func on(workPackagesGenerated event: RuntimeEvents.WorkReportGenerated) async throws {
        await storage.packageRefined(packageHashes: event.items.map(\.packageSpecification.workPackageHash))
    }

    public func getPendingPackages() async -> [WorkPackageRef] {
        await storage.getPendingPackages()
    }
}
