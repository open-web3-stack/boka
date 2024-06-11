import Utils

public struct JudgementsState {
    // ψa: The allow-set contains the hashes of all work-reports which were disputed and judged to be accurate.
    public var allowSet: Set<H256>

    // ψb: The ban-set contains the hashes of all work-reports which were disputed and whose accuracy
    // could not be confidently confirmed.
    public var banSet: Set<H256>

    // ψp; he punish-set is a set of keys of Bandersnatch keys which were found to have guaranteed
    // a report which was confidently found to be invalid.
    public var punishSet: Set<BandersnatchPublicKey>
}
