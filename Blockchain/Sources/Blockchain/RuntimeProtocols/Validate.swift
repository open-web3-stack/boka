import Utils

public protocol Validate: HasConfig {
    func validate(config: Config) throws

    // only validate self without validating child
    // used by default implementation of validate
    func validateSelf(config: Config) throws
}

public enum ValidateError: Error {
    case invalidConfigType
    case childError(field: String?, error: Error)
}

extension Validate {
    private func validateTypeErased(config: Any) throws {
        guard let config = config as? Config else {
            throw ValidateError.invalidConfigType
        }
        try validate(config: config)
    }

    public func validate(config: Config) throws {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if let value = child.value as? any Validate {
                try Result { try value.validateTypeErased(config: config) }
                    .mapError { ValidateError.childError(field: child.label, error: $0) }
                    .get()
            }
        }

        try validateSelf(config: config)
    }

    public func validateSelf(config _: Config) throws {}
}

public struct Validated<T: Validate> {
    public let value: T

    public init(config: T.Config, value: T) throws {
        self.value = value
        try value.validate(config: config)
    }
}

extension Validate {
    public func toValidated(config: Config) throws -> Validated<Self> {
        try Validated(config: config, value: self)
    }
}

extension Array where Element: Validate {
    public func validate(config: Element.Config) throws {
        for item in self {
            try item.validate(config: config)
        }
    }
}

extension ConfigLimitedSizeArray: Validate where T: Validate {
    public func validate(config: Config) throws {
        try array.validate(config: config)
    }
}

extension LimitedSizeArray: Validate where T: Validate {
    public func validate(config: Config) throws {
        try array.validate(config: config)
    }
}

extension Ref: Validate where T: Validate {
    public func validate(config: Config) throws {
        try value.validate(config: config)
    }
}
