import PolkaVM
import Utils

// constants defined in the graypaper
public struct ProtocolConfig: Sendable {
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
    public var coreAccumulationGas: Int

    // GI: The gas allocated to invoke a work-package’s Is-Authorized logic.
    public var workPackageAuthorizerGas: Int

    // GR: The total gas allocated for a work-package’s Refine logic.
    public var workPackageRefineGas: Int

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
        coreAccumulationGas: Int,
        workPackageAuthorizerGas: Int,
        workPackageRefineGas: Int,
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

    public enum CoreAccumulationGas: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.coreAccumulationGas
        }
    }

    public enum WorkPackageAuthorizerGas: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
            config.value.workPackageAuthorizerGas
        }
    }

    public enum WorkPackageRefineGas: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: ProtocolConfigRef) -> Int {
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
