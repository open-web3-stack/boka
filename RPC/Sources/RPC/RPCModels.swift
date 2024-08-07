import Blockchain
import Utils
import Vapor

public struct RPCRequest<T: Content>: Content {
    public let jsonrpc: String
    public let method: String
    public let params: T?
    public let id: Int?
}

public struct RPCResponse<T: Content>: Content {
    public let jsonrpc: String
    public let result: T?
    public let error: RPCError?
    public let id: Int?
}

public struct RPCError: Content, Error {
    public let code: Int
    public let message: String
}

public struct RPCParams: Content {
    // Generic params structure if needed
}

public struct RPCResult: Content {
    // Generic result structure if needed
}

public struct BlockParams: Content {
    let blockHash: String?
}

public struct HeaderParams: Content {
    let blockHash: String?
}

public struct CodableBlock: Codable {
    let property1: String
    let property2: String
    // Add all properties from the original Block type

    init(from block: Block) {
        property1 = block.header.parentHash.description
        property2 = block.header.extrinsicsRoot.description
        // Initialize all properties from the original Block type
    }
}

public struct CodableHeader: Codable {
    let property1: String
    let property2: String

    init(from header: Header) {
        property1 = header.parentHash.description
        property2 = header.extrinsicsRoot.description
    }
}

public struct AnyContent: Content {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        if let value = value as? CodableBlock {
            try value.encode(to: encoder)
        } else if let value = value as? CodableHeader {
            try value.encode(to: encoder)
        } else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Assuming a common set of types we expect
        if let value = try? container.decode(CodableBlock.self) {
            self.value = value
        } else if let value = try? container.decode(CodableHeader.self) {
            self.value = value
        } else {
            value = ""
        }
    }
}
