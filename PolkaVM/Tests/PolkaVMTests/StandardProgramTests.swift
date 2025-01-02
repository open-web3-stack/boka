@testable import Blockchain
import Foundation
import PolkaVM
import Testing

struct StandardProgramTests {
    func createBlob() -> Data {
        let readOnlyLen: UInt32 = 256
        let readWriteLen: UInt32 = 512
        let heapPages: UInt16 = 4
        let stackSize: UInt32 = 1024
        let codeLength: UInt32 = 6

        let readOnlyData = Data(repeating: 0x01, count: Int(readOnlyLen))
        let readWriteData = Data(repeating: 0x02, count: Int(readWriteLen))
        let codeData = Data([0, 0, 2, 1, 2, 0])

        var blob = Data()
        blob.append(contentsOf: withUnsafeBytes(of: readOnlyLen.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(contentsOf: withUnsafeBytes(of: readWriteLen.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(contentsOf: withUnsafeBytes(of: heapPages.bigEndian) { Array($0) })
        blob.append(contentsOf: withUnsafeBytes(of: stackSize.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(readOnlyData)
        blob.append(readWriteData)
        blob.append(contentsOf: Array(codeLength.encode(method: .fixedWidth(4))))
        blob.append(codeData)

        return blob
    }

    @Test func initialization() throws {
        print("createBlob = \(createBlob().toHexString())")
        _ = try StandardProgram(blob: createBlob(), argumentData: nil)
    }
}
