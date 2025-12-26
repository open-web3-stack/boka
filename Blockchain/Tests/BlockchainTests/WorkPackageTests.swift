import Foundation
#if DISABLED
    // Disabled: Needs refactoring for API changes
    import Testing

    @testable import Blockchain

    struct WorkPackageTests {
        @Test
        func workPackageEncodeAndDecode() throws {
            let workPackage = WorkPackage.dummy(config: .minimal)
            let data = try workPackage.encode()
            #expect(data.count > 0)
            let wp = try WorkPackage.decode(data: data, withConfig: ProtocolConfigRef.minimal)
            #expect(wp == workPackage)
        }
    }
#endif
