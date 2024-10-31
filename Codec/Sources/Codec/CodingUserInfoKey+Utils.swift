extension CodingUserInfoKey {
    public static let config = CodingUserInfoKey(rawValue: "config")!
    public static let isJamCodec = CodingUserInfoKey(rawValue: "isJamCodec")!
}

public class ConfigRef<C> {
    public var value: C?

    public init(_ value: C? = nil) {
        self.value = value
    }
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
        if let config = userInfo[.config] as? C {
            return config
        }
        if let config = userInfo[.config] as? ConfigRef<C> {
            return config.value
        }
        return nil
    }

    public func setConfig<C>(_ config: C) {
        if let ref = userInfo[.config] as? ConfigRef<C> {
            ref.value = config
        }
    }
}
