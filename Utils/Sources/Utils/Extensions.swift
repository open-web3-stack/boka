import Foundation

extension Data {
    init?(fromHexString hexString: String) {
        guard !hexString.isEmpty else {
            return nil
        }

        var data = Data()
        var index = hexString.startIndex

        while index < hexString.endIndex {
            guard let nextIndex = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex),
                  let byte = UInt8(hexString[index ..< nextIndex], radix: 16)
            else {
                return nil
            }

            data.append(byte)
            index = nextIndex
        }

        self.init(data)
    }
}
