import Foundation

extension Data {
    public init?(fromHexString hexString: String) {
        guard !hexString.isEmpty else {
            self.init()
            return
        }

        var data = Data()
        var index = hexString.startIndex

        while index < hexString.endIndex {
            guard
                let nextIndex = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex),
                let byte = UInt8(hexString[index ..< nextIndex], radix: 16)
            else {
                return nil
            }

            data.append(byte)
            index = nextIndex
        }

        self.init(data)
    }

    public func toHexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
