import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct ReportsTestcaseState: Codable, Equatable {
    var reports: ConfigFixedSizeArray<ReportItem?, ProtocolConfig.TotalNumberOfCores>
    var currentValidators:
        ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var previousValidators:
        ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var entropyPool: EntropyPool
    var offenders: [Ed25519PublicKey]
    var recentHistory: RecentHistory
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.MaxAuthorizationsPoolItems>,
        ProtocolConfig.TotalNumberOfCores
    >
    @CodingAs<SortedKeyValues<ServiceIndex, ServiceAccountDetails>> var services: [ServiceIndex: ServiceAccountDetails]
    // NOTE: we are not updating stats in guaranteeing STF
    var coresStatistics: ConfigFixedSizeArray<Statistics.Core, ProtocolConfig.TotalNumberOfCores>
    @CodingAs<SortedKeyValues<ServiceIndex, Statistics.Service>> var servicesStatistics: [ServiceIndex: Statistics.Service]
}

struct ReportsInput: Codable {
    var reports: ExtrinsicGuarantees
    var timeslot: TimeslotIndex
    var knownPackages: [Data32]
}

struct ReportedPackage: Codable, Equatable {
    var workPackageHash: Data32
    var segmentRoot: Data32
}

struct ReportsOutput: Codable, Equatable {
    var reported: [ReportedPackage]
    var reporters: [Ed25519PublicKey]
}

struct ReportsState: Guaranteeing {
    var reports: ConfigFixedSizeArray<ReportItem?, ProtocolConfig.TotalNumberOfCores>
    var currentValidators:
        ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var previousValidators:
        ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var entropyPool: EntropyPool
    var offenders: Set<Ed25519PublicKey>
    var recentHistory: RecentHistory
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.MaxAuthorizationsPoolItems>,
        ProtocolConfig.TotalNumberOfCores
    >
    var services: [ServiceIndex: ServiceAccountDetails]

    func serviceAccount(index: ServiceIndex) -> ServiceAccountDetails? {
        services[index]
    }

    var accumulationQueue: ConfigFixedSizeArray<[AccumulationQueueItem], ProtocolConfig.EpochLength>
    var accumulationHistory: ConfigFixedSizeArray<SortedUniqueArray<Data32>, ProtocolConfig.EpochLength>
}

struct ReportsTestcase: Codable {
    var input: ReportsInput
    var preState: ReportsTestcaseState
    var output: Either<ReportsOutput, UInt8>
    var postState: ReportsTestcaseState
}

struct ReportsTests {
    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "stf/reports/\(variant)", extension: "bin")
    }

    func reportsTests(_ testcase: Testcase, variant: TestVariants) throws {
        if testcase.description == "no_enough_guarantees-1.bin" {
            // we can't decode such test because it is intentially invalid
            return
        }

        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(ReportsTestcase.self)

        let state = ReportsState(
            reports: testcase.preState.reports,
            currentValidators: testcase.preState.currentValidators,
            previousValidators: testcase.preState.previousValidators,
            entropyPool: testcase.preState.entropyPool,
            offenders: Set(testcase.preState.offenders),
            recentHistory: testcase.preState.recentHistory,
            coreAuthorizationPool: testcase.preState.coreAuthorizationPool,
            services: testcase.preState.services,
            accumulationQueue: try! ConfigFixedSizeArray(config: config, defaultValue: []),
            accumulationHistory: try! ConfigFixedSizeArray(config: config, defaultValue: .init())
        )
        let result = Result {
            try testcase.input.reports.validate(config: config)
            return try state.update(
                config: config,
                timeslot: testcase.input.timeslot,
                extrinsic: testcase.input.reports
            )
        }
        switch result {
        case let .success((newReports, reported, reporters)):
            switch testcase.output {
            case let .left(output):
                let expectedPostState = ReportsTestcaseState(
                    reports: newReports,
                    currentValidators: state.currentValidators,
                    previousValidators: state.previousValidators,
                    entropyPool: state.entropyPool,
                    offenders: state.offenders.sorted(),
                    recentHistory: state.recentHistory,
                    coreAuthorizationPool: state.coreAuthorizationPool,
                    services: state.services,
                    // NOTE: just use testcase postState since we don't udpate stats in guaranteeing STF
                    coresStatistics: testcase.postState.coresStatistics,
                    servicesStatistics: testcase.postState.servicesStatistics
                )
                let expectedOutput = ReportsOutput(
                    reported: reported.map { report in
                        ReportedPackage(
                            workPackageHash: report.packageSpecification.workPackageHash,
                            segmentRoot: report.packageSpecification.segmentRoot
                        )
                    },
                    reporters: reporters
                )
                #expect(expectedPostState == testcase.postState)
                #expect(expectedOutput == output)
            case .right:
                Issue.record("Expected error, got \(result)")
            }
        case .failure:
            switch testcase.output {
            case .left:
                Issue.record("Expected success, got \(result)")
            case .right:
                // ignore error code because it is unspecified
                break
            }
        }
    }

    @Test(arguments: try ReportsTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        try reportsTests(testcase, variant: .tiny)
    }

    @Test(arguments: try ReportsTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) throws {
        try reportsTests(testcase, variant: .full)
    }
}
