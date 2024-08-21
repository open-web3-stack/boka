import Foundation

public protocol FixedLengthData {
    var data: Data { get }

    static func length(decoder: Decoder) -> Int
    init(decoder: Decoder, data: Data) throws
}
