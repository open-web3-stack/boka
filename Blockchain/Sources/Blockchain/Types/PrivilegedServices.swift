import Codec
import Utils

public struct PrivilegedServices: Sendable, Equatable, Codable {
    // m
    public var empower: ServiceIndex
    // a
    public var assign: ServiceIndex
    // v
    public var designate: ServiceIndex
    // g
    @CodingAs<SortedKeyValues<ServiceIndex, Gas>> public var basicGas: [ServiceIndex: Gas]

    public init(empower: ServiceIndex, assign: ServiceIndex, designate: ServiceIndex, basicGas: [ServiceIndex: Gas]) {
        self.empower = empower
        self.assign = assign
        self.designate = designate
        self.basicGas = basicGas
    }
}
