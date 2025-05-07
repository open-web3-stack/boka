public protocol ReadInt {
    associatedtype TConfig: Sendable
    static func read(config: TConfig) -> Int
}

public protocol ReadUInt64 {
    associatedtype TConfig: Sendable
    static func read(config: TConfig) -> UInt64
}

public protocol ReadGas {
    associatedtype TConfig: Sendable
    static func read(config: TConfig) -> Gas
}
