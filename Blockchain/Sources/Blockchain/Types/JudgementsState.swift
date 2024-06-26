import ScaleCodec
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

    public init(
        allowSet: Set<H256>,
        banSet: Set<H256>,
        punishSet: Set<BandersnatchPublicKey>
    ) {
        self.allowSet = allowSet
        self.banSet = banSet
        self.punishSet = punishSet
    }
}

extension JudgementsState: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig _: Config) -> JudgementsState {
        JudgementsState(
            allowSet: [],
            banSet: [],
            punishSet: []
        )
    }
}

extension JudgementsState: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            allowSet: decoder.decode(),
            banSet: decoder.decode(),
            punishSet: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(allowSet)
        try encoder.encode(banSet)
        try encoder.encode(punishSet)
    }
}
