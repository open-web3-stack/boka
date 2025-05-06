import Synchronization

extension CodingUserInfoKey {
    public static let config = CodingUserInfoKey(rawValue: "config")!
    public static let isJamCodec = CodingUserInfoKey(rawValue: "isJamCodec")!
}

public final class ConfigRef<C: Sendable>: Sendable {
    let value: Mutex<C?>

    public init(_ value: C? = nil) {
        self.value = .init(value)
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

    public func getConfig<C: Sendable>(_: C.Type) -> C? {
        if let config = userInfo[.config] as? C {
            return config
        }
        if let config = userInfo[.config] as? ConfigRef<C> {
            return config.value.withLock {
                $0
            }
        }
        return nil
    }

    public func setConfig<C: Sendable>(_ config: C) {
        if let ref = userInfo[.config] as? ConfigRef<C> {
            ref.value.withLock { value in
                value = config
            }
        }
    }
}
