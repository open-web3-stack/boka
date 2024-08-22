import Foundation

public protocol FixedLengthData {
    var data: Data { get }

    static func length(decoder: Decoder) throws -> Int
    init(decoder: Decoder, data: Data) throws
}
