import Foundation

public struct AtomicDictionary<Key: Hashable, Value> {
    private var dictionary: [Key: Value]
    private let queue = DispatchQueue(label: "com.atomicDictionary.queue", attributes: .concurrent)

    public init() {
        dictionary = [:]
    }

    public init(_ elements: [Key: Value]) {
        dictionary = elements
    }

    private func read<R>(_ block: () throws -> R) rethrows -> R {
        try queue.sync {
            try block()
        }
    }

    private func write<R>(_ block: () throws -> R) rethrows -> R {
        try queue.sync(flags: .barrier) {
            try block()
        }
    }

    public subscript(key: Key) -> Value? {
        get {
            read {
                dictionary[key]
            }
        }
        set {
            write {
                dictionary[key] = newValue
            }
        }
    }

    public mutating func set(value: Value, forKey key: Key) {
        write {
            dictionary[key] = value
        }
    }

    public func value(forKey key: Key) -> Value? {
        read {
            dictionary[key]
        }
    }

    public var count: Int {
        read {
            dictionary.count
        }
    }

    public var isEmpty: Bool {
        read {
            dictionary.isEmpty
        }
    }

    public var keys: [Key] {
        read {
            Array(dictionary.keys)
        }
    }

    public var values: [Value] {
        read {
            Array(dictionary.values)
        }
    }

    public func contains(key: Key) -> Bool {
        read {
            dictionary.keys.contains(key)
        }
    }

    public mutating func removeValue(forKey key: Key) -> Value? {
        write {
            dictionary.removeValue(forKey: key)
        }
    }

    public mutating func removeAll() {
        write {
            dictionary.removeAll()
        }
    }

    public mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        write {
            dictionary.updateValue(value, forKey: key)
        }
    }

    public func forEach(_ body: ((key: Key, value: Value)) throws -> Void) rethrows {
        try read {
            try dictionary.forEach(body)
        }
    }

    public func filter(_ isIncluded: ((key: Key, value: Value)) throws -> Bool) rethrows -> AtomicDictionary {
        try read {
            let filtered = try dictionary.filter(isIncluded)
            return AtomicDictionary(filtered)
        }
    }

    public mutating func merge(_ other: [Key: Value], uniquingKeysWith combine: (Value, Value) throws -> Value) rethrows {
        try write {
            try dictionary.merge(other, uniquingKeysWith: combine)
        }
    }

    public mutating func merge(_ other: AtomicDictionary, uniquingKeysWith combine: (Value, Value) throws -> Value) rethrows {
        try write {
            try dictionary.merge(other.dictionary, uniquingKeysWith: combine)
        }
    }

    public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> AtomicDictionary<Key, T> {
        try read {
            let mapped = try dictionary.mapValues(transform)
            return AtomicDictionary<Key, T>(mapped)
        }
    }

    public func compactMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> AtomicDictionary<Key, T> {
        try read {
            let compactMapped = try dictionary.compactMapValues(transform)
            return AtomicDictionary<Key, T>(compactMapped)
        }
    }
}

// Equatable conformance
extension AtomicDictionary: Equatable where Value: Equatable {
    public static func == (lhs: AtomicDictionary<Key, Value>, rhs: AtomicDictionary<Key, Value>) -> Bool {
        lhs.read {
            rhs.read {
                lhs.dictionary == rhs.dictionary
            }
        }
    }
}
