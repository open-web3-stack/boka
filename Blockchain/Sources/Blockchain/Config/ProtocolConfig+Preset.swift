import Utils

extension Ref where T == ProtocolConfig {
    // TODO: pick some good numbers for dev env
    public static let dev = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 341,
        preimagePurgePeriod: 28800,
        epochLength: 12,
        auditBiasFactor: 2,
        coreAccumulationGas: Gas(10_000_000), // TODO: check this
        workPackageAuthorizerGas: Gas(10_000_000), // TODO: check this
        workPackageRefineGas: Gas(10_000_000), // TODO: check this
        recentHistorySize: 8,
        maxWorkItems: 4,
        maxTicketsPerExtrinsic: 16,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 10,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 6,
        erasureCodedPieceSize: 684,
        maxWorkPackageManifestEntries: 1 << 11,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        maxEncodedWorkReportSize: 96 * 1 << 10,
        erasureCodedSegmentSize: 6,
        ticketSubmissionEndSlot: 10,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitPageSize: 1 << 14,
        pvmProgramInitSegmentSize: 1 << 16
    ))

    public static let mainnet = Ref(ProtocolConfig(
        auditTranchePeriod: 8,
        additionalMinBalancePerStateItem: 10,
        additionalMinBalancePerStateByte: 1,
        serviceMinBalance: 100,
        totalNumberOfCores: 341,
        preimagePurgePeriod: 28800,
        epochLength: 600,
        auditBiasFactor: 2,
        coreAccumulationGas: Gas(10_000_000), // TODO: check this
        workPackageAuthorizerGas: Gas(10_000_000), // TODO: check this
        workPackageRefineGas: Gas(10_000_000), // TODO: check this
        recentHistorySize: 8,
        maxWorkItems: 4,
        maxTicketsPerExtrinsic: 16,
        maxLookupAnchorAge: 14400,
        transferMemoSize: 128,
        ticketEntriesPerValidator: 2,
        maxAuthorizationsPoolItems: 8,
        slotPeriodSeconds: 6,
        maxAuthorizationsQueueItems: 80,
        coreAssignmentRotationPeriod: 10,
        maxServiceCodeSize: 4_000_000,
        preimageReplacementPeriod: 5,
        totalNumberOfValidators: 1023,
        erasureCodedPieceSize: 684,
        maxWorkPackageManifestEntries: 1 << 11,
        maxEncodedWorkPackageSize: 12 * 1 << 20,
        maxEncodedWorkReportSize: 96 * 1 << 10,
        erasureCodedSegmentSize: 6,
        ticketSubmissionEndSlot: 500,
        pvmDynamicAddressAlignmentFactor: 2,
        pvmProgramInitInputDataSize: 1 << 24,
        pvmProgramInitPageSize: 1 << 14,
        pvmProgramInitSegmentSize: 1 << 16
    ))
}
