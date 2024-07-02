import Testing

@testable import JAMTests

struct SafroleTests {
    @Test func works() throws {
        try TestLoader.discover(forPath: "safrole/tiny")
        #expect(1 + 1 == 2)
    }
}
