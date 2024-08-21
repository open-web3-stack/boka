extension CodingUserInfoKey {
    public static let config = CodingUserInfoKey(rawValue: "config")!
    public static let isJamCodec = CodingUserInfoKey(rawValue: "isJamCodec")!
}

extension Encoder {
    public var isJamCodec: Bool {
        userInfo[.isJamCodec] as? Bool ?? false
    }

    public func getConfig<C>() -> C? {
        userInfo[.config] as? C
    }
}

extension Decoder {
    public var isJamCodec: Bool {
        userInfo[.isJamCodec] as? Bool ?? false
    }

    public func getConfig<C>(_: C.Type) -> C? {
        userInfo[.config] as? C
    }
}
