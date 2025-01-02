import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct State: Equatable, Codable {
    // alpha
    var coreAuthorizationPool: StateKeys.CoreAuthorizationPoolKey.Value
    // varphi
    var authorizationQueue: StateKeys.AuthorizationQueueKey.Value
    // beta
    var recentHistory: StateKeys.RecentHistoryKey.Value
    // gamma
    var safroleState: StateKeys.SafroleStateKey.Value
    // psi
    var judgements: StateKeys.JudgementsKey.Value
    // eta
    var entropyPool: EntropyPool
    // iota
    var validatorQueue: StateKeys.ValidatorQueueKey.Value
    // kappa
    var currentValidators: StateKeys.CurrentValidatorsKey.Value
    // lambda
    var previousValidators: StateKeys.PreviousValidatorsKey.Value
    // rho
    var reports: StateKeys.ReportsKey.Value
    // tau
    var timeslot: UInt32
    // chi
    var privilegedServices: StateKeys.PrivilegedServicesKey.Value
    // pi
    var activityStatistics: StateKeys.ActivityStatisticsKey.Value
    // theta
    var accumulationQueue: StateKeys.AccumulationQueueKey.Value
    // xi
    var accumulationHistory: StateKeys.AccumulationHistoryKey.Value
    // service_account
    var serviceAccounts: [ServiceIndex: ServiceAccount]

    var offenders: [Ed25519PublicKey]

    public mutating func mergeWith(postState: State) {
        coreAuthorizationPool = postState.coreAuthorizationPool
        authorizationQueue = postState.authorizationQueue
        recentHistory = postState.recentHistory
        safroleState = postState.safroleState
        judgements = postState.judgements
        entropyPool = postState.entropyPool
        validatorQueue = postState.validatorQueue
        currentValidators = postState.currentValidators
        previousValidators = postState.previousValidators
        reports = postState.reports
        timeslot = postState.timeslot
        privilegedServices = postState.privilegedServices
        activityStatistics = postState.activityStatistics
        accumulationQueue = postState.accumulationQueue
        accumulationHistory = postState.accumulationHistory
        serviceAccounts = postState.serviceAccounts
    }
}

extension State: Safrole {
    public var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { safroleState.nextValidators }

    public var ticketsAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    > { safroleState.ticketsAccumulator }

    public var ticketsOrKeys: Either<
        ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >,
        ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.EpochLength
        >
    > { safroleState.ticketsOrKeys }

    public var ticketsVerifier: BandersnatchRingVRFRoot { safroleState.ticketsVerifier }

    public mutating func mergeWith(postState: SafrolePostState) {
        safroleState.nextValidators = postState.nextValidators
        safroleState.ticketsVerifier = postState.ticketsVerifier
        safroleState.ticketsOrKeys = postState.ticketsOrKeys
        safroleState.ticketsAccumulator = postState.ticketsAccumulator
        entropyPool = postState.entropyPool
        validatorQueue = postState.validatorQueue
        currentValidators = postState.currentValidators
        previousValidators = postState.previousValidators
        timeslot = postState.timeslot
    }
}

struct JamTestnetSafroleTests {
    struct SafroleTestcase: Codable {
        var preState: State
        var block: Block
        var postState: State
    }

    static func loadTest(blockNum: String) throws -> SafroleTestcase {
        let config = TestVariants.tiny.config
        let preStateBin = try TestLoader.getFile(path: "safrole/state_snapshots/\(blockNum)", extension: "bin", src: .jamtestnet)
        let preState = try JamDecoder.decode(State.self, from: preStateBin, withConfig: config)

        let blockBin = try TestLoader.getFile(path: "safrole/blocks/\(blockNum)", extension: "bin", src: .jamtestnet)
        let block = try JamDecoder.decode(Block.self, from: blockBin, withConfig: config)

        let nextBlockNum = String(format: "%06d_%03d", Int(blockNum.prefix(6))!, Int(blockNum.suffix(3))! + 1)
        let postStateBin = try TestLoader.getFile(path: "safrole/state_snapshots/\(nextBlockNum)", extension: "bin", src: .jamtestnet)
        let postState = try JamDecoder.decode(State.self, from: postStateBin, withConfig: config)

        return SafroleTestcase(preState: preState, block: block, postState: postState)
    }

    static func loadTests() throws -> [SafroleTestcase] {
        let blockNumbers = try TestLoader.getFilenames(path: "safrole/state_snapshots", extension: "bin", src: .jamtestnet)
            .map { $0.description.replacingOccurrences(of: ".bin", with: "") }
            .sorted()

        return try blockNumbers.map { try loadTest(blockNum: $0) }
    }

    @Test(arguments: try JamTestnetSafroleTests.loadTests())
    func safroleTests(_ testcase: SafroleTestcase) throws {
        let config = TestVariants.tiny.config

        let result = Result {
            try testcase.block.extrinsic.validate(config: config)
            return try testcase.preState.updateSafrole(
                config: config,
                slot: testcase.block.header.timeslot,
                entropy: testcase.preState.entropyPool.t0,
                offenders: Set(testcase.preState.offenders),
                extrinsics: testcase.block.extrinsic.tickets
            )
        }
        switch result {
        case let .success((state, epochMark, ticketsMark)):
            #expect(epochMark == testcase.block.header.epoch)
            #expect(ticketsMark == testcase.block.header.winningTickets)
            var postState = testcase.preState
            postState.mergeWith(postState: state)
            #expect(postState == testcase.postState)
        case .failure:
            Issue.record("Expected success, got \(result)")
        }
    }
}
