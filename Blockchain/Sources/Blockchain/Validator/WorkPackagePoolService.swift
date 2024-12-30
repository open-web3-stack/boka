import TracingUtils
import Utils

private actor WorkPackageStorage {
    var logger: Logger!
    var workPackages: SortedUniqueArray<WorkPackageAndOutput> = .init()
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

    func add(packages: [WorkPackageAndOutput], config: ProtocolConfigRef) {
        for package in packages {
            guard validatePackage(package, config: config) else {
                logger.warning("Invalid work package: \(package)")
                continue
            }
            workPackages.append(contentsOf: [package])
        }
    }

    private func validatePackage(_: WorkPackageAndOutput, config _: ProtocolConfigRef) -> Bool {
        // TODO: add validate logic
        true
    }

    func removeWorkPackages(_ packages: [WorkPackageAndOutput]) {
        workPackages.remove { workPackage in
            packages.contains { $0 == workPackage }
        }
    }

    func getWorkPackage() -> SortedUniqueArray<WorkPackageAndOutput> {
        workPackages
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

        await subscribe(RuntimeEvents.WorkPackagesGenerated.self, id: "WorkPackagePool.WorkPackagesGenerated") { [weak self] event in
            try await self?.on(workPackagesGenerated: event)
        }
        // TODO: add remove subscribe
        // TODO: add receive subscribe?
    }

    private func on(workPackagesGenerated event: RuntimeEvents.WorkPackagesGenerated) async throws {
        let state = try await dataProvider.getBestState()
        try await storage.update(state: state, config: config)
        await storage.add(packages: event.items, config: config)
    }

    public func update(state: StateRef, config: ProtocolConfigRef) async throws {
        try await storage.update(state: state, config: config)
    }

    public func addWorkPackages(packages: [WorkPackageAndOutput]) async throws {
        await storage.add(packages: packages, config: config)
    }

    public func getWorkPackage() async -> SortedUniqueArray<WorkPackageAndOutput> {
        await storage.getWorkPackage()
    }
}
