@testable import Blockchain
import Foundation
import Utils

func data31(_ byte: UInt8) -> Data31 {
    Data31(Data(repeating: byte, count: 31))!
}

func data32(_ byte: UInt8) -> Data32 {
    Data32(Data(repeating: byte, count: 32))!
}

func data64(_ byte: UInt8) -> Data64 {
    Data64(Data(repeating: byte, count: 64))!
}

func data128(_ byte: UInt8) -> Data128 {
    Data128(Data(repeating: byte, count: 128))!
}

