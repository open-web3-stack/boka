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
    @CodingAs<SortedKeyValues<ServiceIndex, Gas>> public var basicGas: [ServiceIndex: Gas]

    public init(blessed: ServiceIndex, assign: ServiceIndex, designate: ServiceIndex, basicGas: [ServiceIndex: Gas]) {
        self.blessed = blessed
        self.assign = assign
        self.designate = designate
        self.basicGas = basicGas
    }
}
