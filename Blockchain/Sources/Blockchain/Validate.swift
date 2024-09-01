import Utils

public protocol Validate: HasConfig {
    func validate(config: Config) throws
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
