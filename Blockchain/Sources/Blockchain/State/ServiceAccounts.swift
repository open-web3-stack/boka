import Foundation
import Utils

public protocol ServiceAccounts: Sendable {
    func get(serviceAccount index: ServiceIndex) async throws -> ServiceAccountDetails?
    func get(serviceAccount index: ServiceIndex, storageKey key: Data) async throws -> Data?
    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data?
    func get(
        serviceAccount index: ServiceIndex, preimageHash hash: Data32, length: UInt32
    ) async throws -> StateKeys.ServiceAccountPreimageInfoKey.Value?

    func historicalLookup(serviceAccount index: ServiceIndex, timeslot: TimeslotIndex, preimageHash hash: Data32) async throws -> Data?

    mutating func set(serviceAccount index: ServiceIndex, account: ServiceAccountDetails?)
    mutating func set(serviceAccount index: ServiceIndex, storageKey key: Data, value: Data?) async throws
    mutating func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data?)
    mutating func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
        value: StateKeys.ServiceAccountPreimageInfoKey.Value?
    ) async throws
}

public class ServiceAccountsRef: Ref<ServiceAccounts>, @unchecked Sendable {}

public class ServiceAccountsMutRef: @unchecked Sendable {
    public let ref: RefMut<ServiceAccounts>
    public private(set) var changes: AccountChanges

    public var value: ServiceAccounts { ref.value }

    public init(_ accounts: ServiceAccounts) {
        ref = RefMut(accounts)
        changes = AccountChanges()
    }

    public func toRef() -> ServiceAccountsRef {
        ServiceAccountsRef(ref.value)
    }

    public func set(serviceAccount index: ServiceIndex, account: ServiceAccountDetails) {
        ref.value.set(serviceAccount: index, account: account)
        changes.addAccountUpdate(index: index, account: account)
    }

    public func set(serviceAccount index: ServiceIndex, storageKey key: Data, value: Data?) async throws {
        try await ref.value.set(serviceAccount: index, storageKey: key, value: value)
        changes.addStorageUpdate(index: index, key: key, value: value)
    }

    public func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data?) {
        ref.value.set(serviceAccount: index, preimageHash: hash, value: value)
        changes.addPreimageUpdate(index: index, hash: hash, value: value)
    }

    public func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
        value: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>?
    ) async throws {
        try await ref.value.set(serviceAccount: index, preimageHash: hash, length: length, value: value)
        changes.addPreimageInfoUpdate(index: index, hash: hash, length: length, value: value)
    }

    public func addNew(serviceAccount index: ServiceIndex, account: ServiceAccount) async throws {
        // set new account details with zero footprint initially
        var accountDetails = account.toDetails()
        accountDetails.itemsCount = 0
        accountDetails.totalByteLength = 0
        ref.value.set(serviceAccount: index, account: accountDetails)

        for (key, value) in account.storage {
            try await ref.value.set(serviceAccount: index, storageKey: key, value: value)
        }
        for (key, value) in account.preimages {
            ref.value.set(serviceAccount: index, preimageHash: key, value: value)
        }
        for (key, value) in account.preimageInfos {
            try await ref.value.set(serviceAccount: index, preimageHash: key.hash, length: key.length, value: value)
        }
        changes.addNewAccount(index: index, account: account)
    }

    public func remove(serviceAccount index: ServiceIndex) {
        ref.value.set(serviceAccount: index, account: nil)
        changes.addRemovedAccount(index: index)
    }

    public func clearRecordedChanges() {
        changes = AccountChanges()
    }
}
