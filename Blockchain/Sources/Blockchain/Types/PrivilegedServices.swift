import Codec
import Utils

public struct PrivilegedServices: Sendable, Equatable, Codable {
    // m
    public var manager: ServiceIndex
    // a
    public var assigners: ConfigFixedSizeArray<ServiceIndex, ProtocolConfig.TotalNumberOfCores>
    // v
    public var delegator: ServiceIndex
    // g or z
    public var alwaysAcc: [ServiceIndex: Gas]

    public init(
        manager: ServiceIndex,
        assigners: ConfigFixedSizeArray<ServiceIndex, ProtocolConfig.TotalNumberOfCores>,
        delegator: ServiceIndex,
        alwaysAcc: [ServiceIndex: Gas]
    ) {
        self.manager = manager
        self.assigners = assigners
        self.delegator = delegator
        self.alwaysAcc = alwaysAcc
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manager = try container.decode(ServiceIndex.self, forKey: .manager)
        assigners = try container.decode(ConfigFixedSizeArray<ServiceIndex, ProtocolConfig.TotalNumberOfCores>.self, forKey: .assigners)
        delegator = try container.decode(ServiceIndex.self, forKey: .delegator)

        let compactGas = try container.decode(SortedKeyValues<ServiceIndex, Compact<Gas>>.self, forKey: .alwaysAcc)
        alwaysAcc = compactGas.alias.mapValues { $0.alias }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manager, forKey: .manager)
        try container.encode(assigners, forKey: .assigners)
        try container.encode(delegator, forKey: .delegator)

        let compactGas = SortedKeyValues(alias: alwaysAcc.mapValues { Compact(alias: $0) })
        try container.encode(compactGas, forKey: .alwaysAcc)
    }

    private enum CodingKeys: String, CodingKey {
        case manager, assigners, delegator, alwaysAcc
    }
}
