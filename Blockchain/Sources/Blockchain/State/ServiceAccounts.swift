import Foundation
import Utils

public protocol ServiceAccounts: Sendable {
    func get(serviceAccount index: ServiceIndex) async throws -> ServiceAccountDetails?
    func get(serviceAccount index: ServiceIndex, storageKey key: Data32) async throws -> Data?
    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data?
    func get(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length: UInt32
    ) async throws -> StateKeys.ServiceAccountPreimageInfoKey.Value?

    func historicalLookup(serviceAccount index: ServiceIndex, timeslot: TimeslotIndex, preimageHash hash: Data32) async throws -> Data?

    mutating func set(serviceAccount index: ServiceIndex, account: ServiceAccountDetails?)
    mutating func set(serviceAccount index: ServiceIndex, storageKey key: Data32, value: Data?)
    mutating func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data?)
    mutating func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
        value: StateKeys.ServiceAccountPreimageInfoKey.Value?
    )
}

public class ServiceAccountsRef: Ref<ServiceAccounts>, @unchecked Sendable {}

public typealias ServiceAccountsMutRef = RefMut<ServiceAccounts>

extension ServiceAccountsMutRef {
    public func toRef() -> ServiceAccountsRef {
        ServiceAccountsRef(value)
    }
}
