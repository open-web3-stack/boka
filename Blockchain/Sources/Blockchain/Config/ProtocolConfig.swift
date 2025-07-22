import Codec
import PolkaVM
import Utils

/// constants defined in the graypaper
public struct ProtocolConfig: Sendable, Codable, Equatable {
    /// A = 8: The period, in seconds, between audit tranches.
    public var auditTranchePeriod: Int

    /// BI = 10: The additional minimum balance required per item of elective service state.
    public var additionalMinBalancePerStateItem: Int

    /// BL = 1: The additional minimum balance required per octet of elective service state.
    public var additionalMinBalancePerStateByte: Int

    /// BS = 100: The basic minimum balance which all services require.
    public var serviceMinBalance: Int

    /// C = 341: The total number of cores.
    public var totalNumberOfCores: Int

    /// D = 19,200: The period in timeslots after which an unreferenced preimage may be expunged.
    public var preimagePurgePeriod: Int

    /// E = 600: The length of an epoch in timeslots.
    public var epochLength: Int

    /// F = 2: The audit bias factor, the expected number of additional validators who will audit a work-report in the
    /// following tranche for each no-show in the previous.
    public var auditBiasFactor: Int

    /// GA = 10,000,000: The gas allocated to invoke a work-report's Accumulation logic.
    public var workReportAccumulationGas: Gas

    /// GI = 50,000,000: The gas allocated to invoke a work-package’s Is-Authorized logic.
    public var workPackageIsAuthorizedGas: Gas

    /// GR = 5,000,000,000: The gas allocated to invoke a work-package's Refine logic.
    public var workPackageRefineGas: Gas

    /// GT: The total gas allocated across for all Accumulation.
    public var totalAccumulationGas: Gas

    /// H = 8: The size of recent history, in blocks.
    public var recentHistorySize: Int

    /// I = 16: The maximum amount of work items in a package.
    public var maxWorkItems: Int

    /// J = 8: The maximum sum of dependency items in a work-report.
    public var maxDepsInWorkReport: Int

    /// K = 16: The maximum number of tickets which may be submitted in a single extrinsic.
    public var maxTicketsPerExtrinsic: Int

    /// L = 14,400: The maximum age in timeslots of the lookup anchor.
    public var maxLookupAnchorAge: Int

    /// N = 2: The number of ticket entries per validator.
    public var ticketEntriesPerValidator: Int

    /// O = 8: The maximum number of items in the authorizations pool.
    public var maxAuthorizationsPoolItems: Int

    /// P = 6: The slot period, in seconds.
    public var slotPeriodSeconds: Int

    /// Q = 80: The number of items in the authorizations queue.
    public var maxAuthorizationsQueueItems: Int

    /// R = 10: The rotation period of validator-core assignments, in timeslots.
    public var coreAssignmentRotationPeriod: Int

    /// S = 1024: The maximum number of entries in the accumulation queue.
    public var maxAccumulationQueueItems: Int

    /// T = 128: The maximum number of extrinsics in a work-package.
    public var maxWorkPackageExtrinsics: Int

    /// U = 5: The period in timeslots after which reported but unavailable work may be replaced.
    public var preimageReplacementPeriod: Int

    /// V = 1023: The total number of validators.
    public var totalNumberOfValidators: Int

    /// WA = 64,000: The maximum size of is-authorized code in octets.
    public var maxIsAuthorizedCodeSize: Int

    /// WB = 12 * 2^20: The maximum size of an encoded work-package together with its extrinsic data and import implications, in octets.
    public var maxEncodedWorkPackageSize: Int

    /// WC = 4,000,000: The maximum size of service code in octets.
    public var maxServiceCodeSize: Int

    /// WE = 684: The basic size of our erasure-coded pieces.
    public var erasureCodedPieceSize: Int

    /// WG = WP*WE = 4104: The size of a segment in octets.
    public var segmentSize: Int

    /// WM = 3,072: The maximum number of imports in a work-package.
    public var maxWorkPackageImports: Int

    /// WP = 6: The number of erasure-coded pieces in a segment.
    public var erasureCodedSegmentSize: Int

    /// WR = 48 * 2^10: The maximum total size of all unbounded blobs in a work-report, in octets.
    public var maxWorkReportBlobSize: Int

    /// WT = 128: The size of a transfer memo in octets.
    public var transferMemoSize: Int

    /// WX = 3,072: The maximum number of exports in a work-package.
    public var maxWorkPackageExports: Int

    /// Y = 500: The number of slots into an epoch at which ticket-submission ends.
    public var ticketSubmissionEndSlot: Int

    /// ZA = 2: The pvm dynamic address alignment factor.
    public var pvmDynamicAddressAlignmentFactor: Int

    /// ZI = 2^24: The standard pvm program initialization input data size.
    public var pvmProgramInitInputDataSize: Int

    /// ZZ = 2^16: The standard pvm program initialization zone size.
    public var pvmProgramInitZoneSize: Int

    /// ZP = 2^12: The pvm memory page size.
    public var pvmMemoryPageSize: Int

    public init(
        auditTranchePeriod: Int,
        additionalMinBalancePerStateItem: Int,
        additionalMinBalancePerStateByte: Int,
        serviceMinBalance: Int,
        totalNumberOfCores: Int,
        preimagePurgePeriod: Int,
        epochLength: Int,
        auditBiasFactor: Int,
        workReportAccumulationGas: Gas,
        workPackageIsAuthorizedGas: Gas,
        workPackageRefineGas: Gas,
        totalAccumulationGas: Gas,
        recentHistorySize: Int,
        maxWorkItems: Int,
        maxDepsInWorkReport: Int,
        maxTicketsPerExtrinsic: Int,
        maxLookupAnchorAge: Int,
        transferMemoSize: Int,
        ticketEntriesPerValidator: Int,
        maxAuthorizationsPoolItems: Int,
        slotPeriodSeconds: Int,
        maxAuthorizationsQueueItems: Int,
        coreAssignmentRotationPeriod: Int,
        maxAccumulationQueueItems: Int,
        maxWorkPackageExtrinsics: Int,
        maxIsAuthorizedCodeSize: Int,
        maxServiceCodeSize: Int,
        preimageReplacementPeriod: Int,
        totalNumberOfValidators: Int,
        erasureCodedPieceSize: Int,
        maxWorkPackageImports: Int,
        maxWorkPackageExports: Int,
        maxEncodedWorkPackageSize: Int,
        segmentSize: Int,
        maxWorkReportBlobSize: Int,
        erasureCodedSegmentSize: Int,
        ticketSubmissionEndSlot: Int,
        pvmDynamicAddressAlignmentFactor: Int,
        pvmProgramInitInputDataSize: Int,
        pvmProgramInitZoneSize: Int,
        pvmMemoryPageSize: Int
    ) {
        self.auditTranchePeriod = auditTranchePeriod
        self.additionalMinBalancePerStateItem = additionalMinBalancePerStateItem
        self.additionalMinBalancePerStateByte = additionalMinBalancePerStateByte
        self.serviceMinBalance = serviceMinBalance
        self.totalNumberOfCores = totalNumberOfCores
        self.preimagePurgePeriod = preimagePurgePeriod
        self.epochLength = epochLength
        self.auditBiasFactor = auditBiasFactor
        self.workReportAccumulationGas = workReportAccumulationGas
        self.workPackageIsAuthorizedGas = workPackageIsAuthorizedGas
        self.workPackageRefineGas = workPackageRefineGas
        self.totalAccumulationGas = totalAccumulationGas
        self.recentHistorySize = recentHistorySize
        self.maxWorkItems = maxWorkItems
        self.maxDepsInWorkReport = maxDepsInWorkReport
        self.maxTicketsPerExtrinsic = maxTicketsPerExtrinsic
        self.maxLookupAnchorAge = maxLookupAnchorAge
        self.transferMemoSize = transferMemoSize
        self.ticketEntriesPerValidator = ticketEntriesPerValidator
        self.maxAuthorizationsPoolItems = maxAuthorizationsPoolItems
        self.slotPeriodSeconds = slotPeriodSeconds
        self.maxAuthorizationsQueueItems = maxAuthorizationsQueueItems
        self.coreAssignmentRotationPeriod = coreAssignmentRotationPeriod
        self.maxAccumulationQueueItems = maxAccumulationQueueItems
        self.maxWorkPackageExtrinsics = maxWorkPackageExtrinsics
        self.maxIsAuthorizedCodeSize = maxIsAuthorizedCodeSize
        self.maxServiceCodeSize = maxServiceCodeSize
        self.preimageReplacementPeriod = preimageReplacementPeriod
        self.totalNumberOfValidators = totalNumberOfValidators
        self.erasureCodedPieceSize = erasureCodedPieceSize
        self.maxWorkPackageImports = maxWorkPackageImports
        self.maxWorkPackageExports = maxWorkPackageExports
        self.maxEncodedWorkPackageSize = maxEncodedWorkPackageSize
        self.segmentSize = segmentSize
        self.maxWorkReportBlobSize = maxWorkReportBlobSize
        self.erasureCodedSegmentSize = erasureCodedSegmentSize
        self.ticketSubmissionEndSlot = ticketSubmissionEndSlot
        self.pvmDynamicAddressAlignmentFactor = pvmDynamicAddressAlignmentFactor
        self.pvmProgramInitInputDataSize = pvmProgramInitInputDataSize
        self.pvmProgramInitZoneSize = pvmProgramInitZoneSize
        self.pvmMemoryPageSize = pvmMemoryPageSize
    }
}

public typealias ProtocolConfigRef = Ref<ProtocolConfig>

extension ProtocolConfig: PvmConfig {}
/// silence the warning about cross module conformances as we owns all the code
extension Ref: @retroactive PvmConfig where T == ProtocolConfig {
    public var pvmDynamicAddressAlignmentFactor: Int { value.pvmDynamicAddressAlignmentFactor }
    public var pvmProgramInitInputDataSize: Int { value.pvmProgramInitInputDataSize }
    public var pvmProgramInitZoneSize: Int { value.pvmProgramInitZoneSize }
    public var pvmMemoryPageSize: Int { value.pvmMemoryPageSize }
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
            workReportAccumulationGas: other.workReportAccumulationGas.value != 0
                ? other.workReportAccumulationGas : workReportAccumulationGas,
            workPackageIsAuthorizedGas: other.workPackageIsAuthorizedGas.value != 0
                ? other.workPackageIsAuthorizedGas : workPackageIsAuthorizedGas,
            workPackageRefineGas: other.workPackageRefineGas.value != 0
                ? other.workPackageRefineGas : workPackageRefineGas,
            totalAccumulationGas: other.totalAccumulationGas.value != 0
                ? other.totalAccumulationGas : totalAccumulationGas,
            recentHistorySize: other.recentHistorySize != 0
                ? other.recentHistorySize : recentHistorySize,
            maxWorkItems: other.maxWorkItems != 0 ? other.maxWorkItems : maxWorkItems,
            maxDepsInWorkReport: other.maxDepsInWorkReport != 0
                ? other.maxDepsInWorkReport : maxDepsInWorkReport,
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
            maxAccumulationQueueItems: other.maxAccumulationQueueItems != 0
                ? other.maxAccumulationQueueItems : maxAccumulationQueueItems,
            maxWorkPackageExtrinsics: other.maxWorkPackageExtrinsics != 0
                ? other.maxWorkPackageExtrinsics : maxWorkPackageExtrinsics,
            maxIsAuthorizedCodeSize: other.maxIsAuthorizedCodeSize != 0
                ? other.maxIsAuthorizedCodeSize : maxIsAuthorizedCodeSize,
            maxServiceCodeSize: other.maxServiceCodeSize != 0
                ? other.maxServiceCodeSize : maxServiceCodeSize,
            preimageReplacementPeriod: other.preimageReplacementPeriod != 0
                ? other.preimageReplacementPeriod : preimageReplacementPeriod,
            totalNumberOfValidators: other.totalNumberOfValidators != 0
                ? other.totalNumberOfValidators : totalNumberOfValidators,
            erasureCodedPieceSize: other.erasureCodedPieceSize != 0
                ? other.erasureCodedPieceSize : erasureCodedPieceSize,
            maxWorkPackageImports: other.maxWorkPackageImports != 0
                ? other.maxWorkPackageImports : maxWorkPackageImports,
            maxWorkPackageExports: other.maxWorkPackageExports != 0
                ? other.maxWorkPackageExports : maxWorkPackageExports,
            maxEncodedWorkPackageSize: other.maxEncodedWorkPackageSize != 0
                ? other.maxEncodedWorkPackageSize : maxEncodedWorkPackageSize,
            segmentSize: other.segmentSize != 0 ? other.segmentSize : segmentSize,
            maxWorkReportBlobSize: other.maxWorkReportBlobSize != 0
                ? other.maxWorkReportBlobSize : maxWorkReportBlobSize,
            erasureCodedSegmentSize: other.erasureCodedSegmentSize != 0
                ? other.erasureCodedSegmentSize : erasureCodedSegmentSize,
            ticketSubmissionEndSlot: other.ticketSubmissionEndSlot != 0
                ? other.ticketSubmissionEndSlot : ticketSubmissionEndSlot,
            pvmDynamicAddressAlignmentFactor: other.pvmDynamicAddressAlignmentFactor != 0
                ? other.pvmDynamicAddressAlignmentFactor : pvmDynamicAddressAlignmentFactor,
            pvmProgramInitInputDataSize: other.pvmProgramInitInputDataSize != 0
                ? other.pvmProgramInitInputDataSize : pvmProgramInitInputDataSize,
            pvmProgramInitZoneSize: other.pvmProgramInitZoneSize != 0
                ? other.pvmProgramInitZoneSize : pvmProgramInitZoneSize,
            pvmMemoryPageSize: other.pvmMemoryPageSize != 0
                ? other.pvmMemoryPageSize : pvmMemoryPageSize
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
        workReportAccumulationGas = try decode(
            .workReportAccumulationGas, defaultValue: Gas(0), required: required
        )
        workPackageIsAuthorizedGas = try decode(
            .workPackageIsAuthorizedGas, defaultValue: Gas(0), required: required
        )
        workPackageRefineGas = try decode(
            .workPackageRefineGas, defaultValue: Gas(0), required: required
        )
        totalAccumulationGas = try decode(
            .totalAccumulationGas, defaultValue: Gas(0), required: required
        )
        recentHistorySize = try decode(.recentHistorySize, defaultValue: 0, required: required)
        maxWorkItems = try decode(.maxWorkItems, defaultValue: 0, required: required)
        maxDepsInWorkReport = try decode(.maxDepsInWorkReport, defaultValue: 0, required: required)
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
        maxAccumulationQueueItems = try decode(
            .maxAccumulationQueueItems, defaultValue: 0, required: required
        )
        maxWorkPackageExtrinsics = try decode(
            .maxWorkPackageExtrinsics, defaultValue: 0, required: required
        )
        maxIsAuthorizedCodeSize = try decode(.maxIsAuthorizedCodeSize, defaultValue: 0, required: required)
        maxServiceCodeSize = try decode(.maxServiceCodeSize, defaultValue: 0, required: required)
        preimageReplacementPeriod = try decode(
            .preimageReplacementPeriod, defaultValue: 0, required: required
        )
        totalNumberOfValidators = try decode(
            .totalNumberOfValidators, defaultValue: 0, required: required
        )
        erasureCodedPieceSize = try decode(.erasureCodedPieceSize, defaultValue: 0, required: required)
        maxWorkPackageImports = try decode(
            .maxWorkPackageImports, defaultValue: 0, required: required
        )
        maxWorkPackageExports = try decode(
            .maxWorkPackageExports, defaultValue: 0, required: required
        )
        maxEncodedWorkPackageSize = try decode(
            .maxEncodedWorkPackageSize, defaultValue: 0, required: required
        )
        segmentSize = try decode(.segmentSize, defaultValue: 0, required: required)
        maxWorkReportBlobSize = try decode(
            .maxWorkReportBlobSize, defaultValue: 0, required: required
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
        pvmProgramInitZoneSize = try decode(
            .pvmProgramInitZoneSize, defaultValue: 0, required: required
        )
        pvmMemoryPageSize = try decode(
            .pvmMemoryPageSize, defaultValue: 0, required: required
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

    public enum WorkReportAccumulationGas: ReadGas {
        public typealias TConfig = ProtocolConfigRef
        public typealias TOutput = Gas
        public static func read(config: ProtocolConfigRef) -> Gas {
            config.value.workReportAccumulationGas
        }
    }

    public enum WorkPackageIsAuthorizedGas: ReadGas {
        public typealias TConfig = ProtocolConfigRef
        public typealias TOutput = Gas
        public static func read(config: ProtocolConfigRef) -> Gas {
            config.value.workPackageIsAuthorizedGas
        }
    }

    public enum WorkPackageRefineGas: ReadGas {
        public typealias TConfig = ProtocolConfigRef
        public typealias TOutput = Gas
        public static func read(config: ProtocolConfigRef) -> Gas {
            config.value.workPackageRefineGas
        }
    }

    public enum TotalAccumulationGas: ReadGas {
        public typealias TConfig = ProtocolConfigRef
        public typealias TOutput = Gas
        public static func read(config: ProtocolConfigRef) -> Gas {
            config.value.totalAccumulationGas
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

    public enum MaxDepsInWorkReport: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxDepsInWorkReport
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

    public enum MaxAccumulationQueueItems: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxAccumulationQueueItems
        }
    }

    public enum MaxWorkPackageExtrinsics: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxWorkPackageExtrinsics
        }
    }

    public enum MaxIsAuthorizedCodeSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxIsAuthorizedCodeSize
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

    public enum MaxWorkPackageImports: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxWorkPackageImports
        }
    }

    public enum MaxEncodedWorkPackageSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxEncodedWorkPackageSize
        }
    }

    public enum SegmentSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.segmentSize
        }
    }

    public enum MaxWorkReportBlobSize: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.maxWorkReportBlobSize
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

extension ProtocolConfig {
    public var encoded: Data {
        try! JamEncoder.encode(
            UInt64(additionalMinBalancePerStateItem),
            UInt64(additionalMinBalancePerStateByte),
            UInt64(serviceMinBalance),
            UInt16(totalNumberOfCores),
            UInt32(preimagePurgePeriod),
            UInt32(epochLength),
            workReportAccumulationGas,
            workPackageIsAuthorizedGas,
            workPackageRefineGas,
            totalAccumulationGas,
            UInt16(recentHistorySize),
            UInt16(maxWorkItems),
            UInt16(maxDepsInWorkReport),
            UInt16(maxTicketsPerExtrinsic),
            UInt32(maxLookupAnchorAge),
            UInt16(ticketEntriesPerValidator),
            UInt16(maxAuthorizationsPoolItems),
            UInt16(slotPeriodSeconds),
            UInt16(maxAuthorizationsQueueItems),
            UInt16(coreAssignmentRotationPeriod),
            UInt16(maxWorkPackageExtrinsics),
            UInt16(preimageReplacementPeriod),
            UInt16(totalNumberOfValidators),
            UInt32(maxIsAuthorizedCodeSize),
            UInt32(maxEncodedWorkPackageSize),
            UInt32(maxServiceCodeSize),
            UInt32(erasureCodedPieceSize),
            UInt32(maxWorkPackageImports),
            UInt32(erasureCodedSegmentSize),
            UInt32(maxWorkReportBlobSize),
            UInt32(transferMemoSize),
            UInt32(maxWorkPackageExports),
            UInt32(ticketSubmissionEndSlot),
        )
    }

    /// Decode ProtocolConfig from encoded parameters.
    public static func decode(protocolParameters: Data) throws -> ProtocolConfig {
        let decoder = JamDecoder(data: protocolParameters, config: ProtocolConfigRef.minimal)

        let additionalMinBalancePerStateItem = try decoder.decode(UInt64.self)
        let additionalMinBalancePerStateByte = try decoder.decode(UInt64.self)
        let serviceMinBalance = try decoder.decode(UInt64.self)
        let totalNumberOfCores = try decoder.decode(UInt16.self)
        let preimagePurgePeriod = try decoder.decode(UInt32.self)
        let epochLength = try decoder.decode(UInt32.self)
        let workReportAccumulationGas = try decoder.decode(Gas.self)
        let workPackageIsAuthorizedGas = try decoder.decode(Gas.self)
        let workPackageRefineGas = try decoder.decode(Gas.self)
        let totalAccumulationGas = try decoder.decode(Gas.self)
        let recentHistorySize = try decoder.decode(UInt16.self)
        let maxWorkItems = try decoder.decode(UInt16.self)
        let maxDepsInWorkReport = try decoder.decode(UInt16.self)
        let maxTicketsPerExtrinsic = try decoder.decode(UInt16.self)
        let maxLookupAnchorAge = try decoder.decode(UInt32.self)
        let ticketEntriesPerValidator = try decoder.decode(UInt16.self)
        let maxAuthorizationsPoolItems = try decoder.decode(UInt16.self)
        let slotPeriodSeconds = try decoder.decode(UInt16.self)
        let maxAuthorizationsQueueItems = try decoder.decode(UInt16.self)
        let coreAssignmentRotationPeriod = try decoder.decode(UInt16.self)
        let maxWorkPackageExtrinsics = try decoder.decode(UInt16.self)
        let preimageReplacementPeriod = try decoder.decode(UInt16.self)
        let totalNumberOfValidators = try decoder.decode(UInt16.self)
        let maxIsAuthorizedCodeSize = try decoder.decode(UInt32.self)
        let maxEncodedWorkPackageSize = try decoder.decode(UInt32.self)
        let maxServiceCodeSize = try decoder.decode(UInt32.self)
        let erasureCodedPieceSize = try decoder.decode(UInt32.self)
        let maxWorkPackageImports = try decoder.decode(UInt32.self)
        let erasureCodedSegmentSize = try decoder.decode(UInt32.self)
        let maxWorkReportBlobSize = try decoder.decode(UInt32.self)
        let transferMemoSize = try decoder.decode(UInt32.self)
        let maxWorkPackageExports = try decoder.decode(UInt32.self)
        let ticketSubmissionEndSlot = try decoder.decode(UInt32.self)

        let protocolConfig = ProtocolConfig(
            auditTranchePeriod: 8, // A = 8
            additionalMinBalancePerStateItem: Int(additionalMinBalancePerStateItem),
            additionalMinBalancePerStateByte: Int(additionalMinBalancePerStateByte),
            serviceMinBalance: Int(serviceMinBalance),
            totalNumberOfCores: Int(totalNumberOfCores),
            preimagePurgePeriod: Int(preimagePurgePeriod),
            epochLength: Int(epochLength),
            auditBiasFactor: 2, // F = 2
            workReportAccumulationGas: workReportAccumulationGas,
            workPackageIsAuthorizedGas: workPackageIsAuthorizedGas,
            workPackageRefineGas: workPackageRefineGas,
            totalAccumulationGas: totalAccumulationGas,
            recentHistorySize: Int(recentHistorySize),
            maxWorkItems: Int(maxWorkItems),
            maxDepsInWorkReport: Int(maxDepsInWorkReport),
            maxTicketsPerExtrinsic: Int(maxTicketsPerExtrinsic),
            maxLookupAnchorAge: Int(maxLookupAnchorAge),
            transferMemoSize: Int(transferMemoSize),
            ticketEntriesPerValidator: Int(ticketEntriesPerValidator),
            maxAuthorizationsPoolItems: Int(maxAuthorizationsPoolItems),
            slotPeriodSeconds: Int(slotPeriodSeconds),
            maxAuthorizationsQueueItems: Int(maxAuthorizationsQueueItems),
            coreAssignmentRotationPeriod: Int(coreAssignmentRotationPeriod),
            maxAccumulationQueueItems: 1024, // S = 1024
            maxWorkPackageExtrinsics: Int(maxWorkPackageExtrinsics),
            maxIsAuthorizedCodeSize: Int(maxIsAuthorizedCodeSize),
            maxServiceCodeSize: Int(maxServiceCodeSize),
            preimageReplacementPeriod: Int(preimageReplacementPeriod),
            totalNumberOfValidators: Int(totalNumberOfValidators),
            erasureCodedPieceSize: Int(erasureCodedPieceSize),
            maxWorkPackageImports: Int(maxWorkPackageImports),
            maxWorkPackageExports: Int(maxWorkPackageExports),
            maxEncodedWorkPackageSize: Int(maxEncodedWorkPackageSize),
            segmentSize: 4104, // WG = WP*WE = 4104
            maxWorkReportBlobSize: Int(maxWorkReportBlobSize),
            erasureCodedSegmentSize: Int(erasureCodedSegmentSize),
            ticketSubmissionEndSlot: Int(ticketSubmissionEndSlot),
            pvmDynamicAddressAlignmentFactor: 2, // ZA = 2
            pvmProgramInitInputDataSize: 1 << 24, // ZI = 2^24
            pvmProgramInitZoneSize: 1 << 16, // ZZ = 2^16
            pvmMemoryPageSize: 1 << 12 // ZP = 2^12
        )

        return protocolConfig
    }
}
