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

public class ServiceAccountsMutRef {
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
        changes.addAlteration(index: index) { accounts in
            accounts.set(serviceAccount: index, account: account)
        }
    }

    public func set(serviceAccount index: ServiceIndex, storageKey key: Data32, value: Data?) {
        ref.value.set(serviceAccount: index, storageKey: key, value: value)
        changes.addAlteration(index: index) { accounts in
            accounts.set(serviceAccount: index, storageKey: key, value: value)
        }
    }

    public func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data?) {
        ref.value.set(serviceAccount: index, preimageHash: hash, value: value)
        changes.addAlteration(index: index) { accounts in
            accounts.set(serviceAccount: index, preimageHash: hash, value: value)
        }
    }

    public func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
        value: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>?
    ) {
        ref.value.set(serviceAccount: index, preimageHash: hash, length: length, value: value)
        changes.addAlteration(index: index) { accounts in
            accounts.set(serviceAccount: index, preimageHash: hash, length: length, value: value)
        }
    }

    public func addNew(serviceAccount index: ServiceIndex, account: ServiceAccount) {
        ref.value.set(serviceAccount: index, account: account.toDetails())
        for (key, value) in account.storage {
            ref.value.set(serviceAccount: index, storageKey: key, value: value)
        }
        for (key, value) in account.preimages {
            ref.value.set(serviceAccount: index, preimageHash: key, value: value)
        }
        for (key, value) in account.preimageInfos {
            ref.value.set(serviceAccount: index, preimageHash: key.hash, length: key.length, value: value)
        }
        changes.newAccounts[index] = account
    }

    public func remove(serviceAccount index: ServiceIndex) {
        ref.value.set(serviceAccount: index, account: nil)
        changes.removed.insert(index)
    }

    public func clearRecordedChanges() {
        changes = AccountChanges()
    }
}
