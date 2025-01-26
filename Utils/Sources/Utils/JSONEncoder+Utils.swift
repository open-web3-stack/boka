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

extension JSONDecoder.DataDecodingStrategy {
    public static var hex: JSONDecoder.DataDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let hexString = try container.decode(String.self)
            guard hexString.hasPrefix("0x"), let data = Data(fromHexString: String(hexString.dropFirst(2))) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hex string")
            }
            return data
        }
    }
}
