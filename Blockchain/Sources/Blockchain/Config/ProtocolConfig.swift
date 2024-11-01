import PolkaVM
import Utils

// constants defined in the graypaper
public struct ProtocolConfig: Sendable, Codable, Equatable {
    // A = 8: The period, in seconds, between audit tranches.
    public var auditTranchePeriod: Int

    // BI = 10: The additional minimum balance required per item of elective service state.
    public var additionalMinBalancePerStateItem: Int

    // BL = 1: The additional minimum balance required per octet of elective service state.
    public var additionalMinBalancePerStateByte: Int

    // BS = 100: The basic minimum balance which all services require.
    public var serviceMinBalance: Int

    // C = 341: The total number of cores.
    public var totalNumberOfCores: Int

    // D = 28, 800: The period in timeslots after which an unreferenced preimage may be expunged.
    public var preimagePurgePeriod: Int

    // E = 600: The length of an epoch in timeslots.
    public var epochLength: Int

    // F = 2: The audit bias factor, the expected number of additional validators who will audit a work-report in the
    // following tranche for each no-show in the previous.
    public var auditBiasFactor: Int

    // GA: The total gas allocated to a core for Accumulation.
    public var coreAccumulationGas: Gas

    // GI: The gas allocated to invoke a work-package’s Is-Authorized logic.
    public var workPackageAuthorizerGas: Gas

    // GR: The total gas allocated for a work-package’s Refine logic.
    public var workPackageRefineGas: Gas

    // H = 8: The size of recent history, in blocks.
    public var recentHistorySize: Int

    // I = 4: The maximum amount of work items in a package.
    public var maxWorkItems: Int

    // K = 16: The maximum number of tickets which may be submitted in a single extrinsic.
    public var maxTicketsPerExtrinsic: Int

    // L = 14, 400: The maximum age in timeslots of the lookup anchor.
    public var maxLookupAnchorAge: Int

    // M = 128: The size of a transfer memo in octets.
    public var transferMemoSize: Int

    // N = 2: The number of ticket entries per validator.
    public var ticketEntriesPerValidator: Int

    // O = 8: The maximum number of items in the authorizations pool.
    public var maxAuthorizationsPoolItems: Int

    // P = 6: The slot period, in seconds.
    public var slotPeriodSeconds: Int

    // Q = 80: The maximum number of items in the authorizations queue.
    public var maxAuthorizationsQueueItems: Int

    // R = 10: The rotation period of validator-core assignments, in timeslots.
    public var coreAssignmentRotationPeriod: Int

    // S = 4,000,000: The maximum size of service code in octets.
    public var maxServiceCodeSize: Int

    // U = 5: The period in timeslots after which reported but unavailable work may be replaced.
    public var preimageReplacementPeriod: Int

    // V = 1023: The total number of validators.
    public var totalNumberOfValidators: Int

    // WC = 684: The basic size of our erasure-coded pieces.
    public var erasureCodedPieceSize: Int

    // WM = 2^11: The maximum number of entries in a work-package manifest.
    public var maxWorkPackageManifestEntries: Int

    // WP = 12 * 2^20: The maximum size of an encoded work-package together with its extrinsic data and import impli-
    // cations, in octets.
    public var maxEncodedWorkPackageSize: Int

    // WR = 96 * 2^10: The maximum size of an encoded work-report in octets.
    public var maxEncodedWorkReportSize: Int

    // WS = 6: The size of an exported segment in erasure-coded pieces.
    public var erasureCodedSegmentSize: Int

    // Y = 500: The number of slots into an epoch at which ticket-submission ends.
    public var ticketSubmissionEndSlot: Int

    // ZA = 2: The pvm dynamic address alignment factor.
    public var pvmDynamicAddressAlignmentFactor: Int

    // ZI = 2^24: The standard pvm program initialization input data size.
    public var pvmProgramInitInputDataSize: Int

    // ZP = 2^14: The standard pvm program initialization page size.
    public var pvmProgramInitPageSize: Int

    // ZQ = 2^16: The standard pvm program initialization segment size.
    public var pvmProgramInitSegmentSize: Int

    public init(
        auditTranchePeriod: Int,
        additionalMinBalancePerStateItem: Int,
        additionalMinBalancePerStateByte: Int,
        serviceMinBalance: Int,
        totalNumberOfCores: Int,
        preimagePurgePeriod: Int,
        epochLength: Int,
        auditBiasFactor: Int,
        coreAccumulationGas: Gas,
        workPackageAuthorizerGas: Gas,
        workPackageRefineGas: Gas,
        recentHistorySize: Int,
        maxWorkItems: Int,
        maxTicketsPerExtrinsic: Int,
        maxLookupAnchorAge: Int,
        transferMemoSize: Int,
        ticketEntriesPerValidator: Int,
        maxAuthorizationsPoolItems: Int,
        slotPeriodSeconds: Int,
        maxAuthorizationsQueueItems: Int,
        coreAssignmentRotationPeriod: Int,
        maxServiceCodeSize: Int,
        preimageReplacementPeriod: Int,
        totalNumberOfValidators: Int,
        erasureCodedPieceSize: Int,
        maxWorkPackageManifestEntries: Int,
        maxEncodedWorkPackageSize: Int,
        maxEncodedWorkReportSize: Int,
        erasureCodedSegmentSize: Int,
        ticketSubmissionEndSlot: Int,
        pvmDynamicAddressAlignmentFactor: Int,
        pvmProgramInitInputDataSize: Int,
        pvmProgramInitPageSize: Int,
        pvmProgramInitSegmentSize: Int
    ) {
        self.auditTranchePeriod = auditTranchePeriod
        self.additionalMinBalancePerStateItem = additionalMinBalancePerStateItem
        self.additionalMinBalancePerStateByte = additionalMinBalancePerStateByte
        self.serviceMinBalance = serviceMinBalance
        self.totalNumberOfCores = totalNumberOfCores
        self.preimagePurgePeriod = preimagePurgePeriod
        self.epochLength = epochLength
        self.auditBiasFactor = auditBiasFactor
        self.coreAccumulationGas = coreAccumulationGas
        self.workPackageAuthorizerGas = workPackageAuthorizerGas
        self.workPackageRefineGas = workPackageRefineGas
        self.recentHistorySize = recentHistorySize
        self.maxWorkItems = maxWorkItems
        self.maxTicketsPerExtrinsic = maxTicketsPerExtrinsic
        self.maxLookupAnchorAge = maxLookupAnchorAge
        self.transferMemoSize = transferMemoSize
        self.ticketEntriesPerValidator = ticketEntriesPerValidator
        self.maxAuthorizationsPoolItems = maxAuthorizationsPoolItems
        self.slotPeriodSeconds = slotPeriodSeconds
        self.maxAuthorizationsQueueItems = maxAuthorizationsQueueItems
        self.coreAssignmentRotationPeriod = coreAssignmentRotationPeriod
        self.maxServiceCodeSize = maxServiceCodeSize
        self.preimageReplacementPeriod = preimageReplacementPeriod
        self.totalNumberOfValidators = totalNumberOfValidators
        self.erasureCodedPieceSize = erasureCodedPieceSize
        self.maxWorkPackageManifestEntries = maxWorkPackageManifestEntries
        self.maxEncodedWorkPackageSize = maxEncodedWorkPackageSize
        self.maxEncodedWorkReportSize = maxEncodedWorkReportSize
        self.erasureCodedSegmentSize = erasureCodedSegmentSize
        self.ticketSubmissionEndSlot = ticketSubmissionEndSlot
        self.pvmDynamicAddressAlignmentFactor = pvmDynamicAddressAlignmentFactor
        self.pvmProgramInitInputDataSize = pvmProgramInitInputDataSize
        self.pvmProgramInitPageSize = pvmProgramInitPageSize
        self.pvmProgramInitSegmentSize = pvmProgramInitSegmentSize
    }
}

public typealias ProtocolConfigRef = Ref<ProtocolConfig>

extension ProtocolConfig: PvmConfig {}
// silence the warning about cross module conformances as we owns all the code
extension Ref: @retroactive PvmConfig where T == ProtocolConfig {
    public var pvmDynamicAddressAlignmentFactor: Int { value.pvmDynamicAddressAlignmentFactor }
    public var pvmProgramInitInputDataSize: Int { value.pvmProgramInitInputDataSize }
    public var pvmProgramInitPageSize: Int { value.pvmProgramInitPageSize }
    public var pvmProgramInitSegmentSize: Int { value.pvmProgramInitSegmentSize }
}

extension ProtocolConfig {
    public func merged(with other: ProtocolConfig) -> ProtocolConfig {
        ProtocolConfig(
            auditTranchePeriod: other.auditTranchePeriod != 0
                ? other.auditTranchePeriod : auditTranchePeriod,
            additionalMinBalancePerStateItem: other.additionalMinBalancePerStateItem != 0
                ? other.additionalMinBalancePerStateItem : additionalMinBalancePerStateItem,
            additionalMinBalancePerStateByte: other.additionalMinBalancePerStateByte != 0
                ? other.additionalMinBalancePerStateByte : additionalMinBalancePerStateByte,
            serviceMinBalance: other.serviceMinBalance != 0
                ? other.serviceMinBalance : serviceMinBalance,
            totalNumberOfCores: other.totalNumberOfCores != 0
                ? other.totalNumberOfCores : totalNumberOfCores,
            preimagePurgePeriod: other.preimagePurgePeriod != 0
                ? other.preimagePurgePeriod : preimagePurgePeriod,
            epochLength: other.epochLength != 0 ? other.epochLength : epochLength,
            auditBiasFactor: other.auditBiasFactor != 0
                ? other.auditBiasFactor : auditBiasFactor,
            coreAccumulationGas: other.coreAccumulationGas.value != 0
                ? other.coreAccumulationGas : coreAccumulationGas,
            workPackageAuthorizerGas: other.workPackageAuthorizerGas.value != 0
                ? other.workPackageAuthorizerGas : workPackageAuthorizerGas,
            workPackageRefineGas: other.workPackageRefineGas.value != 0
                ? other.workPackageRefineGas : workPackageRefineGas,
            recentHistorySize: other.recentHistorySize != 0
                ? other.recentHistorySize : recentHistorySize,
            maxWorkItems: other.maxWorkItems != 0 ? other.maxWorkItems : maxWorkItems,
            maxTicketsPerExtrinsic: other.maxTicketsPerExtrinsic != 0
                ? other.maxTicketsPerExtrinsic : maxTicketsPerExtrinsic,
            maxLookupAnchorAge: other.maxLookupAnchorAge != 0
                ? other.maxLookupAnchorAge : maxLookupAnchorAge,
            transferMemoSize: other.transferMemoSize != 0
                ? other.transferMemoSize : transferMemoSize,
            ticketEntriesPerValidator: other.ticketEntriesPerValidator != 0
                ? other.ticketEntriesPerValidator : ticketEntriesPerValidator,
            maxAuthorizationsPoolItems: other.maxAuthorizationsPoolItems != 0
                ? other.maxAuthorizationsPoolItems : maxAuthorizationsPoolItems,
            slotPeriodSeconds: other.slotPeriodSeconds != 0
                ? other.slotPeriodSeconds : slotPeriodSeconds,
            maxAuthorizationsQueueItems: other.maxAuthorizationsQueueItems != 0
                ? other.maxAuthorizationsQueueItems : maxAuthorizationsQueueItems,
            coreAssignmentRotationPeriod: other.coreAssignmentRotationPeriod != 0
                ? other.coreAssignmentRotationPeriod : coreAssignmentRotationPeriod,
            maxServiceCodeSize: other.maxServiceCodeSize != 0
                ? other.maxServiceCodeSize : maxServiceCodeSize,
            preimageReplacementPeriod: other.preimageReplacementPeriod != 0
                ? other.preimageReplacementPeriod : preimageReplacementPeriod,
            totalNumberOfValidators: other.totalNumberOfValidators != 0
                ? other.totalNumberOfValidators : totalNumberOfValidators,
            erasureCodedPieceSize: other.erasureCodedPieceSize != 0
                ? other.erasureCodedPieceSize : erasureCodedPieceSize,
            maxWorkPackageManifestEntries: other.maxWorkPackageManifestEntries != 0
                ? other.maxWorkPackageManifestEntries : maxWorkPackageManifestEntries,
            maxEncodedWorkPackageSize: other.maxEncodedWorkPackageSize != 0
                ? other.maxEncodedWorkPackageSize : maxEncodedWorkPackageSize,
            maxEncodedWorkReportSize: other.maxEncodedWorkReportSize != 0
                ? other.maxEncodedWorkReportSize : maxEncodedWorkReportSize,
            erasureCodedSegmentSize: other.erasureCodedSegmentSize != 0
                ? other.erasureCodedSegmentSize : erasureCodedSegmentSize,
            ticketSubmissionEndSlot: other.ticketSubmissionEndSlot != 0
                ? other.ticketSubmissionEndSlot : ticketSubmissionEndSlot,
            pvmDynamicAddressAlignmentFactor: other.pvmDynamicAddressAlignmentFactor != 0
                ? other.pvmDynamicAddressAlignmentFactor : pvmDynamicAddressAlignmentFactor,
            pvmProgramInitInputDataSize: other.pvmProgramInitInputDataSize != 0
                ? other.pvmProgramInitInputDataSize : pvmProgramInitInputDataSize,
            pvmProgramInitPageSize: other.pvmProgramInitPageSize != 0
                ? other.pvmProgramInitPageSize : pvmProgramInitPageSize,
            pvmProgramInitSegmentSize: other.pvmProgramInitSegmentSize != 0
                ? other.pvmProgramInitSegmentSize : pvmProgramInitSegmentSize
        )
    }

    public init(from decoder: Decoder, _ required: Bool = false) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func decode<T: Decodable>(_ key: CodingKeys, defaultValue: T, required: Bool) throws -> T {
            if required {
                try container.decode(T.self, forKey: key)
            } else {
                try container.decodeIfPresent(T.self, forKey: key) ?? defaultValue
            }
        }

        auditTranchePeriod = try decode(.auditTranchePeriod, defaultValue: 0, required: required)
        additionalMinBalancePerStateItem = try decode(
            .additionalMinBalancePerStateItem, defaultValue: 0, required: required
        )
        additionalMinBalancePerStateByte = try decode(
            .additionalMinBalancePerStateByte, defaultValue: 0, required: required
        )
        serviceMinBalance = try decode(.serviceMinBalance, defaultValue: 0, required: required)
        totalNumberOfCores = try decode(.totalNumberOfCores, defaultValue: 0, required: required)
        preimagePurgePeriod = try decode(.preimagePurgePeriod, defaultValue: 0, required: required)
        epochLength = try decode(.epochLength, defaultValue: 0, required: required)
        auditBiasFactor = try decode(.auditBiasFactor, defaultValue: 0, required: required)
        coreAccumulationGas = try decode(
            .coreAccumulationGas, defaultValue: Gas(0), required: required
        )
        workPackageAuthorizerGas = try decode(
            .workPackageAuthorizerGas, defaultValue: Gas(0), required: required
        )
        workPackageRefineGas = try decode(
            .workPackageRefineGas, defaultValue: Gas(0), required: required
        )
        recentHistorySize = try decode(.recentHistorySize, defaultValue: 0, required: required)
        maxWorkItems = try decode(.maxWorkItems, defaultValue: 0, required: required)
        maxTicketsPerExtrinsic = try decode(
            .maxTicketsPerExtrinsic, defaultValue: 0, required: required
        )
        maxLookupAnchorAge = try decode(.maxLookupAnchorAge, defaultValue: 0, required: required)
        transferMemoSize = try decode(.transferMemoSize, defaultValue: 0, required: required)
        ticketEntriesPerValidator = try decode(
            .ticketEntriesPerValidator, defaultValue: 0, required: required
        )
        maxAuthorizationsPoolItems = try decode(
            .maxAuthorizationsPoolItems, defaultValue: 0, required: required
        )
        slotPeriodSeconds = try decode(.slotPeriodSeconds, defaultValue: 0, required: required)
        maxAuthorizationsQueueItems = try decode(
            .maxAuthorizationsQueueItems, defaultValue: 0, required: required
        )
        coreAssignmentRotationPeriod = try decode(
            .coreAssignmentRotationPeriod, defaultValue: 0, required: required
        )
        maxServiceCodeSize = try decode(.maxServiceCodeSize, defaultValue: 0, required: required)
        preimageReplacementPeriod = try decode(
            .preimageReplacementPeriod, defaultValue: 0, required: required
        )
        totalNumberOfValidators = try decode(
            .totalNumberOfValidators, defaultValue: 0, required: required
        )
        erasureCodedPieceSize = try decode(.erasureCodedPieceSize, defaultValue: 0, required: required)
        maxWorkPackageManifestEntries = try decode(
            .maxWorkPackageManifestEntries, defaultValue: 0, required: required
        )
        maxEncodedWorkPackageSize = try decode(
            .maxEncodedWorkPackageSize, defaultValue: 0, required: required
        )
        maxEncodedWorkReportSize = try decode(
            .maxEncodedWorkReportSize, defaultValue: 0, required: required
        )
        erasureCodedSegmentSize = try decode(
            .erasureCodedSegmentSize, defaultValue: 0, required: required
        )
        ticketSubmissionEndSlot = try decode(
            .ticketSubmissionEndSlot, defaultValue: 0, required: required
        )
        pvmDynamicAddressAlignmentFactor = try decode(
            .pvmDynamicAddressAlignmentFactor, defaultValue: 0, required: required
        )
        pvmProgramInitInputDataSize = try decode(
            .pvmProgramInitInputDataSize, defaultValue: 0, required: required
        )
        pvmProgramInitPageSize = try decode(
            .pvmProgramInitPageSize, defaultValue: 0, required: required
        )
        pvmProgramInitSegmentSize = try decode(
            .pvmProgramInitSegmentSize, defaultValue: 0, required: required
        )
    }
}

extension ProtocolConfig {
    public enum AuditTranchePeriod: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.auditTranchePeriod
        }
    }

    public enum AdditionalMinBalancePerStateItem: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.additionalMinBalancePerStateItem
        }
    }

    public enum AdditionalMinBalancePerStateByte: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.additionalMinBalancePerStateByte
        }
    }

    public enum ServiceMinBalance: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.serviceMinBalance
        }
    }

    public enum TotalNumberOfCores: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.totalNumberOfCores
        }
    }

    public enum PreimagePurgePeriod: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.preimagePurgePeriod
        }
    }

    public enum EpochLength: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.epochLength
        }
    }

    public enum AuditBiasFactor: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.auditBiasFactor
        }
    }

    public enum CoreAccumulationGas: ReadGas {
        public typealias TConfig = ProtocolConfigRef
        public typealias TOutput = Gas
        public static func read(config: ProtocolConfigRef) -> Gas {
            config.value.coreAccumulationGas
        }
    }

    public enum WorkPackageAuthorizerGas: ReadGas {
        public typealias TConfig = ProtocolConfigRef
        public typealias TOutput = Gas
        public static func read(config: ProtocolConfigRef) -> Gas {
            config.value.workPackageAuthorizerGas
        }
    }

    public enum WorkPackageRefineGas: ReadGas {
        public typealias TConfig = ProtocolConfigRef
        public typealias TOutput = Gas
        public static func read(config: ProtocolConfigRef) -> Gas {
            config.value.workPackageRefineGas
        }
    }

    public enum RecentHistorySize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.recentHistorySize
        }
    }

    public enum MaxWorkItems: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxWorkItems
        }
    }

    public enum MaxTicketsPerExtrinsic: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxTicketsPerExtrinsic
        }
    }

    public enum MaxLookupAnchorAge: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxLookupAnchorAge
        }
    }

    public enum TransferMemoSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.transferMemoSize
        }
    }

    public enum TicketEntriesPerValidator: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.ticketEntriesPerValidator
        }
    }

    public enum MaxAuthorizationsPoolItems: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxAuthorizationsPoolItems
        }
    }

    public enum SlotPeriodSeconds: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.slotPeriodSeconds
        }
    }

    public enum MaxAuthorizationsQueueItems: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxAuthorizationsQueueItems
        }
    }

    public enum CoreAssignmentRotationPeriod: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.coreAssignmentRotationPeriod
        }
    }

    public enum MaxServiceCodeSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxServiceCodeSize
        }
    }

    public enum PreimageReplacementPeriod: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.preimageReplacementPeriod
        }
    }

    public enum TotalNumberOfValidators: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.totalNumberOfValidators
        }
    }

    public enum ErasureCodedPieceSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.erasureCodedPieceSize
        }
    }

    public enum MaxWorkPackageManifestEntries: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxWorkPackageManifestEntries
        }
    }

    public enum MaxEncodedWorkPackageSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxEncodedWorkPackageSize
        }
    }

    public enum MaxEncodedWorkReportSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxEncodedWorkReportSize
        }
    }

    public enum ErasureCodedSegmentSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.erasureCodedSegmentSize
        }
    }

    public enum TicketSubmissionEndSlot: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.ticketSubmissionEndSlot
        }
    }

    public enum PvmDynamicAddressAlignmentFactor: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.pvmDynamicAddressAlignmentFactor
        }
    }

    public enum PvmProgramInitInputDataSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.pvmProgramInitInputDataSize
        }
    }

    public enum TwoThirdValidatorsPlusOne: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.totalNumberOfValidators * 2 / 3 + 1
        }
    }
}

extension ProtocolConfig {
    public enum Int0: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config _: ProtocolConfigRef) -> Int {
            0
        }
    }

    public enum Int1: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config _: ProtocolConfigRef) -> Int {
            1
        }
    }
}
