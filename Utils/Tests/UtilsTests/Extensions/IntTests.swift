import Testing
@testable import Utils

struct IntUtilsTests {
    @Test func mod() {
        #expect((1 %% 5) == 1)
        #expect((0 %% 5) == 0)
        #expect((-1 %% 5) == 4)
        #expect((5 %% 3) == 2)
        #expect((-5 %% 3) == 1)
        #expect((-1 %% 3) == 2)
        #expect((-10 %% 3) == 2)
        #expect((-10 %% -3) == -1)
    }
}
