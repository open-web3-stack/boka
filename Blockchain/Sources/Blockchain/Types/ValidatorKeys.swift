import Utils

/// GP 0.8.0 validator sequences have between 6 and 3C entries.
public typealias ValidatorKeys = ConfigLimitedSizeArray<ValidatorKey, ProtocolConfig.MinValidators, ProtocolConfig.MaxValidators>

extension ProtocolConfig {
    public enum MinValidators: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config _: TConfig) -> Int {
            6
        }
    }

    public enum MaxValidators: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config: TConfig) -> Int {
            3 * config.value.totalNumberOfCores
        }
    }
}
