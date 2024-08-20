extension Result: Codable where Success: Codable, Failure: Codable {
    private enum CodingKeys: String, CodingKey {
        case success, failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.success) {
            let success = try container.decode(Success.self, forKey: .success)
            self = .success(success)
        } else if container.contains(.failure) {
            let failure = try container.decode(Failure.self, forKey: .failure)
            self = .failure(failure)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid Result: must contain either success or failure"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .success(success):
            try container.encode(success, forKey: .success)
        case let .failure(failure):
            try container.encode(failure, forKey: .failure)
        }
    }
}
