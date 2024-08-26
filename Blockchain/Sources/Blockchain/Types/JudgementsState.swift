import Utils

// TODO: figure out how to deal with orders for items in Set
public struct JudgementsState: Sendable, Equatable, Codable {
    // ψg: Work-reports judged to be correct
    public var goodSet: Set<Data32>

    // ψb: Work-reports judged to be incorrect
    public var banSet: Set<Data32>

    // ψw: Work-reports whose validity is judged to be unknowable
    public var wonkySet: Set<Data32>

    // ψo: Validators who made a judgement found to be incorrect
    public var punishSet: Set<Ed25519PublicKey>

    public init(
        goodSet: Set<Data32>,
        banSet: Set<Data32>,
        wonkySet: Set<Data32>,
        punishSet: Set<Ed25519PublicKey>
    ) {
        self.goodSet = goodSet
        self.banSet = banSet
        self.wonkySet = wonkySet
        self.punishSet = punishSet
    }
}

extension JudgementsState: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> JudgementsState {
        JudgementsState(
            goodSet: [],
            banSet: [],
            wonkySet: [],
            punishSet: []
        )
    }
}
