import Foundation

extension JSONEncoder.DataEncodingStrategy {
    public static var hex: JSONEncoder.DataEncodingStrategy {
        .custom { data, encoder in
            let hexString = "0x" + data.toHexString()
            var container = encoder.singleValueContainer()
            try container.encode(hexString)
        }
    }
}
