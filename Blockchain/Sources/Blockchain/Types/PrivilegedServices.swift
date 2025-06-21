import Codec
import Utils

public struct PrivilegedServices: Sendable, Equatable, Codable {
    // m
    public var blessed: ServiceIndex
    // a
    public var assign: ServiceIndex
    // v
    public var designate: ServiceIndex
    // g
    public var basicGas: [ServiceIndex: Gas]

    public init(blessed: ServiceIndex, assign: ServiceIndex, designate: ServiceIndex, basicGas: [ServiceIndex: Gas]) {
        self.blessed = blessed
        self.assign = assign
        self.designate = designate
        self.basicGas = basicGas
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blessed = try container.decode(ServiceIndex.self, forKey: .blessed)
        assign = try container.decode(ServiceIndex.self, forKey: .assign)
        designate = try container.decode(ServiceIndex.self, forKey: .designate)

        let compactGas = try container.decode(SortedKeyValues<ServiceIndex, Compact<Gas>>.self, forKey: .basicGas)
        basicGas = compactGas.alias.mapValues { $0.alias }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blessed, forKey: .blessed)
        try container.encode(assign, forKey: .assign)
        try container.encode(designate, forKey: .designate)

        let compactGas = SortedKeyValues(alias: basicGas.mapValues { Compact(alias: $0) })
        try container.encode(compactGas, forKey: .basicGas)
    }

    private enum CodingKeys: String, CodingKey {
        case blessed, assign, designate, basicGas
    }
}
