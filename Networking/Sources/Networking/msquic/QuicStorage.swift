import Foundation
import msquic

struct QuicConnectionEvent {
    var type: Int
}

struct QuicStorage {
    var conn: HQuic
    var config: HQuic
    var stream: HQuic
    var refCount: Atomic<Int>

    init(conn: HQuic, config: HQuic, stream: HQuic, refCount: Int) {
        self.conn = conn
        self.config = config
        self.stream = stream
        self.refCount = Atomic(wrappedValue: refCount)
    }
}

@propertyWrapper
struct Atomic<Value> {
    private var value: Value
    private let lock = NSLock()

    init(wrappedValue value: Value) {
        self.value = value
    }

    var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    mutating func fetchAndSub(_ subValue: Value) -> Value where Value: Numeric {
        lock.lock()
        defer { lock.unlock() }
        let oldValue = value
        value -= subValue
        return oldValue
    }
}
