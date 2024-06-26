public protocol ReadInt {
    associatedtype TConfig
    static func read(config: TConfig) -> Int
}
