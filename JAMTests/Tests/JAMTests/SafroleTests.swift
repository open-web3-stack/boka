import Blockchain
import ScaleCodec
import Testing
import Utils

@testable import JAMTests

struct SafroleInput {
    var slot: UInt32
    var entropy: Data32
    var extrinsics: ExtrinsicTickets
}

struct SafroleTests {
    @Test func works() throws {
        let tinyTests = try TestLoader.getTestFiles(path: "safrole/tiny", extension: "scale")
        print(tinyTests)
        #expect(1 + 1 == 2)
    }
}
