import Blockchain
import Foundation
import Testing

@testable import Node

struct WorkPackageTests {
    @Test
    func workPackageEncodeAndDecode() throws {
        let workPackage = WorkPackage.dummy(config: .minimal)
        let WorkPackageSubmissionMessage = WorkPackageSubmissionMessage(coreIndex: 0, workPackage: workPackage, extrinsics: [])
        let data = try WorkPackageSubmissionMessage.encode()
        #expect(data.count > 0)
        let message = try WorkPackageSubmissionMessage.decode(data: data, withConfig: ProtocolConfigRef.minimal)
        #expect(WorkPackageSubmissionMessage == message)
    }
}
