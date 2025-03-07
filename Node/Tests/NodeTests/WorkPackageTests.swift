import Blockchain
import Foundation
import Testing

@testable import Node

struct WorkPackageTests {
    @Test
    func workPackageEncodeAndDecode() throws {
        let workPackage = WorkPackage.dummy(config: .minimal)
        let workPackageMessage = WorkPackageMessage(coreIndex: 0, workPackage: workPackage, extrinsics: [])
        let data = try workPackageMessage.encode()
        #expect(data.count > 0)
        let message = try WorkPackageMessage.decode(data: data, withConfig: ProtocolConfigRef.minimal)
        #expect(workPackageMessage == message)
    }
}
