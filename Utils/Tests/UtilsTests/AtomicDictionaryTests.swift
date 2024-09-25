import Foundation
import Testing

@testable import Utils

struct AtomicDictionaryTests {
    @Test func initDictionary() throws {
        let dict = AtomicDictionary<String, Int>()
        #expect(dict.count == 0)
        #expect(dict.isEmpty)
    }

    @Test func initWithElements() throws {
        let elements = ["one": 1, "two": 2, "three": 3]
        let dict = AtomicDictionary(elements)
        #expect(dict.count == 3)
        #expect(dict.value(forKey: "one") == 1)
        #expect(dict.value(forKey: "two") == 2)
        #expect(dict.value(forKey: "three") == 3)
    }

    @Test func subscriptAccess() throws {
        var dict = AtomicDictionary<String, Int>()
        dict["one"] = 1
        dict["two"] = 2
        #expect(dict["one"] == 1)
        #expect(dict["two"] == 2)
        #expect(dict.count == 2)
    }

    @Test func setValue() throws {
        var dict = AtomicDictionary<String, Int>()
        dict.set(value: 1, forKey: "one")
        dict.set(value: 2, forKey: "two")
        #expect(dict.value(forKey: "one") == 1)
        #expect(dict.value(forKey: "two") == 2)
        #expect(dict.count == 2)
    }

    @Test func removeValue() throws {
        var dict = AtomicDictionary<String, Int>(["one": 1, "two": 2, "three": 3])
        let removedValue = dict.removeValue(forKey: "two")
        #expect(removedValue == 2)
        #expect(dict.count == 2)
        #expect(dict.value(forKey: "two") == nil)
    }

    @Test func removeAllValues() throws {
        var dict = AtomicDictionary<String, Int>(["one": 1, "two": 2, "three": 3])
        dict.removeAll()
        #expect(dict.count == 0)
        #expect(dict.isEmpty)
    }

    @Test func updateValue() throws {
        var dict = AtomicDictionary<String, Int>(["one": 1, "two": 2])
        let oldValue = dict.updateValue(3, forKey: "two")
        #expect(oldValue == 2)
        #expect(dict.value(forKey: "two") == 3)
    }

    @Test func containsKey() throws {
        let dict = AtomicDictionary<String, Int>(["one": 1, "two": 2])
        #expect(dict.contains(key: "one"))
        #expect(!dict.contains(key: "three"))
    }

    @Test func keysAndValues() throws {
        let dict = AtomicDictionary<String, Int>(["one": 1, "two": 2, "three": 3])
        let keys = dict.keys
        let values = dict.values
        #expect(keys.contains("one"))
        #expect(keys.contains("two"))
        #expect(keys.contains("three"))
        #expect(values.contains(1))
        #expect(values.contains(2))
        #expect(values.contains(3))
    }

    @Test func forEach() throws {
        let dict = AtomicDictionary<String, Int>(["one": 1, "two": 2, "three": 3])
        var sum = 0
        dict.forEach { _, value in
            sum += value
        }
        #expect(sum == 6)
    }

    @Test func filter() throws {
        let dict = AtomicDictionary<String, Int>(["one": 1, "two": 2, "three": 3])
        let filtered = dict.filter { _, value in
            value > 1
        }
        #expect(filtered.count == 2)
        #expect(filtered.value(forKey: "two") == 2)
        #expect(filtered.value(forKey: "three") == 3)
    }

    @Test func mergeDictionaries() throws {
        var dict = AtomicDictionary<String, Int>(["one": 1, "two": 2])
        let otherDict = ["two": 3, "three": 3]
        dict.merge(otherDict) { current, _ in current }
        #expect(dict.count == 3)
        #expect(dict.value(forKey: "two") == 2)
        #expect(dict.value(forKey: "three") == 3)
    }

    @Test func mergeAtomicDictionaries() throws {
        var dict = AtomicDictionary<String, Int>(["one": 1, "two": 2])
        let otherDict = AtomicDictionary<String, Int>(["two": 3, "three": 3])
        dict.merge(otherDict) { current, _ in current }
        #expect(dict.count == 3)
        #expect(dict.value(forKey: "two") == 2)
        #expect(dict.value(forKey: "three") == 3)
    }

    @Test func mapValues() throws {
        let dict = AtomicDictionary<String, Int>(["one": 1, "two": 2, "three": 3])
        let mapped = dict.mapValues { value in
            value * 2
        }
        #expect(mapped.count == 3)
        #expect(mapped.value(forKey: "one") == 2)
        #expect(mapped.value(forKey: "two") == 4)
        #expect(mapped.value(forKey: "three") == 6)
    }

    @Test func compactMapValues() throws {
        let dict = AtomicDictionary<String, Int>(["one": 1, "two": 2, "three": 3])
        let compactMapped = dict.compactMapValues { value in
            value % 2 == 0 ? nil : value
        }
        #expect(compactMapped.count == 2)
        #expect(compactMapped.value(forKey: "one") == 1)
        #expect(compactMapped.value(forKey: "three") == 3)
    }

    @Test func equatable() throws {
        let dict1 = AtomicDictionary<String, Int>(["one": 1, "two": 2])
        let dict2 = AtomicDictionary<String, Int>(["one": 1, "two": 2])
        let dict3 = AtomicDictionary<String, Int>(["one": 1, "three": 3])
        #expect(dict1 == dict2)
        #expect(dict1 != dict3)
    }
}
