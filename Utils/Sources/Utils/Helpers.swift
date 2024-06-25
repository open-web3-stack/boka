import Foundation

public func hexStringToData(_ hexString: String) -> Data? {
    var data = Data()
    var index = hexString.startIndex

    while index < hexString.endIndex {
        // Find the next 2 characters (1 byte)
        guard let nextIndex = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex),
              let byte = UInt8(hexString[index ..< nextIndex], radix: 16)
        else {
            return nil
        }

        data.append(byte)
        index = nextIndex
    }

    return data
}
