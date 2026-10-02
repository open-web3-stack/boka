import Codec
import Utils

public protocol Accumulation: ServiceAccounts {
    var timeslot: TimeslotIndex { get }
    var privilegedServices: PrivilegedServices { get set }
    var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators,
    > { get set }
    var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems,
        >,
        ProtocolConfig.TotalNumberOfCores,
    > { get set }
    var accumulationQueue: StateKeys.AccumulationQueueKey.Value { get set }
    var accumulationHistory: StateKeys.AccumulationHistoryKey.Value { get set }
}
