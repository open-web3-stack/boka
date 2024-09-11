public protocol ReadInt {
    associatedtype TConfig
    static func read(config: TConfig) -> Int
}

public protocol ReadUInt64 {
    associatedtype TConfig
    static func read(config: TConfig) -> UInt64
}
