import Foundation

struct AtomicMap<Key: Hashable, Value> {
    private var dictionary: [Key: Value]
    private let queue = DispatchQueue(label: "com.atomicMap.queue", attributes: .concurrent)

    init() {
        dictionary = [:]
    }

    init(_ elements: [Key: Value]) {
        dictionary = elements
    }

    fileprivate func _read<R>(_ block: () throws -> R) rethrows -> R {
        var result: R!
        try queue.sync {
            result = try block()
        }
        return result
    }

    fileprivate func _write<R>(_ block: () throws -> R) rethrows -> R {
        var result: R!
        try queue.sync(flags: .barrier) {
            result = try block()
        }
        return result
    }

    public mutating func updateValue(_ value: Value, forKey key: Key) {
        _write {
            dictionary.updateValue(value, forKey: key)
        }
    }

    public mutating func removeValue(forKey key: Key) {
        _write {
            dictionary.removeValue(forKey: key)
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

    public func contains(key: Key) -> Bool {
        _read {
            dictionary.keys.contains(key)
        }
    }

    public var keys: Dictionary<Key, Value>.Keys {
        _read {
            dictionary.keys
        }
    }

    public var values: Dictionary<Key, Value>.Values {
        _read {
            dictionary.values
        }
    }

    public var allKeys: [Key] {
        _read {
            Array(dictionary.keys)
        }
    }

    public var allValues: [Value] {
        _read {
            Array(dictionary.values)
        }
    }

    public func forEach(_ body: ((key: Key, value: Value)) throws -> Void) rethrows {
        try _read {
            try dictionary.forEach(body)
        }
    }

    public mutating func removeAll() {
        _write {
            dictionary.removeAll()
        }
    }

    public mutating func setDictionary(_ newDictionary: [Key: Value]) {
        _write {
            dictionary = newDictionary
        }
    }

    public func getDictionary() -> [Key: Value] {
        _read {
            dictionary
        }
    }

    subscript(key: Key) -> Value? {
        get {
            _read {
                dictionary[key]
            }
        }
        set(value) {
            _write {
                dictionary[key] = value
            }
        }
    }
}

extension AtomicMap: CustomStringConvertible {
    var description: String {
        _read {
            "\(dictionary)"
        }
    }
}
