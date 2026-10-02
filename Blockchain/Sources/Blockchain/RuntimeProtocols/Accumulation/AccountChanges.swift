import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "Accumulation")

public struct AccountChanges: Sendable {
    public enum UpdateKind: Sendable {
        case newAccount(ServiceIndex, ServiceAccount)
        case removeAccount(ServiceIndex)
        case updateAccount(ServiceIndex, ServiceAccountDetails)
        case updateStorage(ServiceIndex, Data, Data?)
        case updatePreimage(ServiceIndex, Data32, Data?)
        case updateLookup(ServiceIndex, Data32, UInt32, StateKeys.ServiceAccountLookupKey.Value?)
    }

    // records for checking conflicts
    public var newAccounts: [ServiceIndex: ServiceAccount]
    public var altered: Set<ServiceIndex>
    public var removed: Set<ServiceIndex>

    /// array for apply sequential updates
    public var updates: [UpdateKind]

    public init() {
        newAccounts = [:]
        altered = []
        removed = []
        updates = []
    }

    public mutating func addNewAccount(index: ServiceIndex, account: ServiceAccount) {
        newAccounts[index] = account
        updates.append(.newAccount(index, account))
    }

    public mutating func addRemovedAccount(index: ServiceIndex) {
        removed.insert(index)
        updates.append(.removeAccount(index))
    }

    public mutating func addAccountUpdate(index: ServiceIndex, account: ServiceAccountDetails) {
        altered.insert(index)
        updates.append(.updateAccount(index, account))
    }

    public mutating func addStorageUpdate(index: ServiceIndex, key: Data, value: Data?) {
        altered.insert(index)
        updates.append(.updateStorage(index, key, value))
    }

    public mutating func addPreimageUpdate(index: ServiceIndex, hash: Data32, value: Data?) {
        altered.insert(index)
        updates.append(.updatePreimage(index, hash, value))
    }

    public mutating func addLookupUpdate(
        index: ServiceIndex,
        hash: Data32,
        length: UInt32,
        value: StateKeys.ServiceAccountLookupKey.Value?,
    ) {
        altered.insert(index)
        updates.append(.updateLookup(index, hash, length, value))
    }

    public func apply(to accounts: ServiceAccountsMutRef) async throws {
        let removedIndices = Set(updates.compactMap { update -> ServiceIndex? in
            if case let .removeAccount(index) = update {
                return index
            }
            return nil
        })

        var pendingRemovals: [ServiceIndex] = []
        var seenRemovals: Set<ServiceIndex> = []

        for update in updates {
            switch update {
            case let .newAccount(index, account):
                guard !removedIndices.contains(index) else { continue }
                try await accounts.addNew(serviceAccount: index, account: account)
            case let .removeAccount(index):
                if seenRemovals.insert(index).inserted {
                    pendingRemovals.append(index)
                }
            case let .updateAccount(index, account):
                guard !removedIndices.contains(index) else { continue }
                accounts.set(serviceAccount: index, account: account)
            case let .updateStorage(index, key, value):
                guard !removedIndices.contains(index) else { continue }
                try await accounts.set(serviceAccount: index, storageKey: key, value: value)
            case let .updatePreimage(index, hash, value):
                guard !removedIndices.contains(index) else { continue }
                accounts.set(serviceAccount: index, preimageHash: hash, value: value)
            case let .updateLookup(index, hash, length, value):
                guard !removedIndices.contains(index) else { continue }
                try await accounts.set(serviceAccount: index, preimageHash: hash, length: length, value: value)
            }
        }

        // Remove accounts last so removal dominates mixed update/remove batches.
        for index in pendingRemovals {
            try await accounts.remove(serviceAccount: index)
        }
    }

    public mutating func checkAndMerge(with other: AccountChanges) throws(AccumulationError) {
        guard Set(newAccounts.keys).isDisjoint(with: other.newAccounts.keys) else {
            logger.debug("new accounts have duplicates, self: \(newAccounts.keys), other: \(other.newAccounts.keys)")
            throw .duplicatedNewService
        }
        guard altered.isDisjoint(with: other.altered) else {
            logger.debug("same service being altered in parallel, self: \(altered), other: \(other.altered)")
            throw .duplicatedContributionToService
        }
        guard removed.isDisjoint(with: other.removed) else {
            logger.debug("removed accounts have duplicates, self: \(removed), other: \(other.removed)")
            throw .duplicatedRemovedService
        }

        for (index, account) in other.newAccounts {
            newAccounts[index] = account
        }
        altered.formUnion(other.altered)
        removed.formUnion(other.removed)
        updates.append(contentsOf: other.updates)
    }
}
