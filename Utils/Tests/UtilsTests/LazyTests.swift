import Testing

@testable import Utils

struct LazyTests {
    @Test func lazyRef() async throws {
        await confirmation { confirm in
            let lazy = Lazy {
                confirm()
                return Ref(42)
            }
            #expect(lazy.value.value == 42)
        }
    }
}
