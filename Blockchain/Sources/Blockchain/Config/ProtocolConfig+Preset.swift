import Utils

extension ProtocolConfig {
    private static let presetMapping: [String: ProtocolConfig] = [
        "minimal": ProtocolConfigRef.minimal.value,
        "dev": ProtocolConfigRef.dev.value,
        "tiny": ProtocolConfigRef.tiny.value,
        "mainnet": ProtocolConfigRef.mainnet.value,
    ]

    public func presetName() -> String? {
        ProtocolConfig.presetMapping.first(where: { $0.value == self })?.key
    }
}

extension Ref where T == ProtocolConfig {
    // TODO: pick some good numbers for dev env
    public static let minimal = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 1,
        preimagePurgePeriod: 19200,
        epochLength: 6,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 4,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 4,
        maxAuthorizationsQueueItems: 10,
        coreAssignmentRotationPeriod: 6,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 3,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 6,
        ticketSubmissionEndSlot: 2,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    // TODO: pick some good numbers for dev env
    public static let dev = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 341,
        preimagePurgePeriod: 19200,
        epochLength: 12,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 16,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 10,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 6,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 6,
        ticketSubmissionEndSlot: 10,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    public static let tiny = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 2,
        preimagePurgePeriod: 19200,
        epochLength: 12,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 3,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 3,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 4,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 6,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 1026,
        ticketSubmissionEndSlot: 10,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    public static let small = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 4,
        preimagePurgePeriod: 19200,
        epochLength: 36,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 3,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 4,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 12,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 513,
        ticketSubmissionEndSlot: 30,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    public static let medium = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 6,
        preimagePurgePeriod: 19200,
        epochLength: 60,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 3,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 4,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 18,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 342,
        ticketSubmissionEndSlot: 50,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    public static let large = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 12,
        preimagePurgePeriod: 19200,
        epochLength: 120,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 3,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 4,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 36,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 171,
        ticketSubmissionEndSlot: 100,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    public static let xlarge = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 36,
        preimagePurgePeriod: 19200,
        epochLength: 240,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 16,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 4,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 108,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 57,
        ticketSubmissionEndSlot: 200,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    public static let x2large = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 114,
        preimagePurgePeriod: 19200,
        epochLength: 300,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 16,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 4,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 342,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 18,
        ticketSubmissionEndSlot: 250,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    public static let x3large = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 228,
        preimagePurgePeriod: 19200,
        epochLength: 600,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 16,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 4,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 684,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 9,
        ticketSubmissionEndSlot: 500,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))

    public static let mainnet = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 341,
        preimagePurgePeriod: 19200,
        epochLength: 600,
        auditBiasFactor: 2,
        workReportAccumulationGas: Gas(10_000_000),
        workPackageAuthorizerGas: Gas(50_000_000),
        workPackageRefineGas: Gas(5_000_000_000),
        totalAccumulationGas: Gas(3_500_000_000),
        recentHistorySize: 8,
        maxWorkItems: 16,
        maxDepsInWorkReport: 8,
        maxTicketsPerExtrinsic: 16,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 10,
        maxWorkPackageExtrinsics: 128,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 1023,
        erasureCodedPieceSize: 684,
        maxWorkPackageImportsExports: 3072,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        segmentSize: 4104,
        maxWorkReportOutputSize: 48 * 1 << 10,
        erasureCodedSegmentSize: 6,
        ticketSubmissionEndSlot: 500,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitZoneSize: 1 << 16,
        pvmMemoryPageSize: 1 << 12
    ))
}
