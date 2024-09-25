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

    private func _read<R>(_ block: () throws -> R) rethrows -> R {
        var result: R!
        try queue.sync {
            result = try block()
        }
        return result
    }

    private func _write<R>(_ block: () throws -> R) rethrows -> R {
        var result: R!
        try queue.sync(flags: .barrier) {
            result = try block()
        }
        return result
    }

    public subscript(key: Key) -> Value? {
        get {
            _read {
                dictionary[key]
            }
        }
        set {
            _write {
                dictionary[key] = newValue
            }
        }
    }

    public mutating func set(value: Value, forKey key: Key) {
        _write {
            dictionary[key] = value
        }
    }

    public func value(forKey key: Key) -> Value? {
        _read {
            dictionary[key]
        }
    }

    public var count: Int {
        _read {
            dictionary.count
        }
    }

    public var isEmpty: Bool {
        _read {
            dictionary.isEmpty
        }
    }

    public var keys: [Key] {
        _read {
            Array(dictionary.keys)
        }
    }

    public var values: [Value] {
        _read {
            Array(dictionary.values)
        }
    }

    public func contains(key: Key) -> Bool {
        _read {
            dictionary.keys.contains(key)
        }
    }

    public mutating func removeValue(forKey key: Key) -> Value? {
        _write {
            dictionary.removeValue(forKey: key)
        }
    }

    public mutating func removeAll() {
        _write {
            dictionary.removeAll()
        }
    }

    public mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        _write {
            dictionary.updateValue(value, forKey: key)
        }
    }

    public func forEach(_ body: ((key: Key, value: Value)) throws -> Void) rethrows {
        try _read {
            try dictionary.forEach(body)
        }
    }

    public func filter(_ isIncluded: ((key: Key, value: Value)) throws -> Bool) rethrows -> AtomicDictionary {
        try _read {
            let filtered = try dictionary.filter(isIncluded)
            return AtomicDictionary(filtered)
        }
    }

    public mutating func merge(_ other: [Key: Value], uniquingKeysWith combine: (Value, Value) throws -> Value) rethrows {
        try _write {
            try dictionary.merge(other, uniquingKeysWith: combine)
        }
    }

    public mutating func merge(_ other: AtomicDictionary, uniquingKeysWith combine: (Value, Value) throws -> Value) rethrows {
        try _write {
            try dictionary.merge(other.dictionary, uniquingKeysWith: combine)
        }
    }

    public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> AtomicDictionary<Key, T> {
        try _read {
            let mapped = try dictionary.mapValues(transform)
            return AtomicDictionary<Key, T>(mapped)
        }
    }

    public func compactMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> AtomicDictionary<Key, T> {
        try _read {
            let compactMapped = try dictionary.compactMapValues(transform)
            return AtomicDictionary<Key, T>(compactMapped)
        }
    }
}

// Equatable conformance
extension AtomicDictionary: Equatable where Value: Equatable {
    public static func == (lhs: AtomicDictionary<Key, Value>, rhs: AtomicDictionary<Key, Value>) -> Bool {
        lhs._read {
            rhs._read {
                lhs.dictionary == rhs.dictionary
            }
        }
    }
}
