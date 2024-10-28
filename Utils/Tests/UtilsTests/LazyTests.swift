import Testing

@testable import Utils

struct LazyTests {
    @Test func lazyRef() throws {
        let called = ManagedAtomic(false)
        let lazy = Lazy {
            let calledValue = called.load(ordering: .relaxed)
            #expect(!calledValue)
            called.store(true, ordering: .relaxed)
            return Ref(42)
        }
        #expect(lazy.value.value == 42)
        let calledValue = called.load(ordering: .relaxed)
        #expect(calledValue)
    }
}
