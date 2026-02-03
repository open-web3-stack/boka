import Testing
@testable import Utils

struct ThreadSafeContainerTests {
    @Test func exchangeValue() {
        let container = ThreadSafeContainer<Int>(10)
        let oldValue = container.exchange(20)
        #expect(oldValue == 10)
        #expect(container.value == 20)
        let previousValue = container.exchange(30)
        #expect(previousValue == 20)
        #expect(container.value == 30)
    }
}
