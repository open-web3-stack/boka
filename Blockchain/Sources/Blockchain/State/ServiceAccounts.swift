import Foundation
import Utils

public protocol ServiceAccounts {
    func get(serviceAccount index: ServiceIndex) async throws -> ServiceAccountDetails?
    func get(serviceAccount index: ServiceIndex, storageKey key: Data32) async throws -> Data?
    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data?
    func get(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length: UInt32
    ) async throws -> StateKeys.ServiceAccountPreimageInfoKey.Value.ValueType

    mutating func set(serviceAccount index: ServiceIndex, account: ServiceAccountDetails)
    mutating func set(serviceAccount index: ServiceIndex, storageKey key: Data32, value: Data)
    mutating func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data)
    mutating func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
        value: StateKeys.ServiceAccountPreimageInfoKey.Value.ValueType
    )

    mutating func remove(serviceAccount index: ServiceIndex)
    mutating func remove(serviceAccount index: ServiceIndex, storageKey key: Data32)
    mutating func remove(serviceAccount index: ServiceIndex, preimageHash hash: Data32)
    mutating func remove(serviceAccount index: ServiceIndex, preimageHash hash: Data32, length: UInt32)
}
