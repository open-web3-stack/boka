import Foundation

public struct Bitstring: Hashable, Sendable {

  /// Total number of bits.
  public let length: Int
  /// Byte storage for bits.
  public let bytes: Data

  /// Initialize with total bit length and byte storage.
  ///
  /// - Parameters:
  ///   - length: Total number of bits.
  ///   - bytes: Byte storage for bits.
  ///
  public init(length: Int, bytes: Data) {
    precondition(bytes.count * 8 >= length)
    self.bytes = bytes
    self.length = length
  }

  /// Initialize with byte data storage.
  ///
  /// The total bit count of the bit string is assumed to be
  /// all the bits the provided in the `bytes` parameter.
  ///
  /// - Parameter bytes: Byte storage for bits.
  ///
  public init(bytes: Data) {
    self.bytes = bytes
    length = bytes.count * 8
  }

  /// Initialize with binaryString.
  ///
  /// - Parameter bitString: String of bit array. Each character of the string must be a `1` or `0`.
  /// - Returns: Initialized ``BitString`` or `nil` if any character of the string is not a `1` or `0`.
  ///
  public init?(_ binaryString: String) {
    // Ensure the string only contains '0' and '1'
    guard binaryString.allSatisfy({ $0 == "0" || $0 == "1" }) else {
      return nil
    }
    let length = binaryString.count
    var bytes = Data(repeating: 0, count: (length + 7) / 8)  // +7 to round up to the nearest byte
    for (index, char) in binaryString.enumerated() {
      if char == "1" {
        let byteIndex = index / 8
        let bitIndex = 7 - (index % 8)
        bytes[byteIndex] |= (1 << bitIndex)
      }
    }
    self.init(length: length, bytes: bytes)
  }

  /// String of bit array as text representation with each character a `0` or `1`.
  public var bitString: String {
    return bytes.map { ($0 != 0) ? "1" : "0" }.joined(separator: "")
  }

  public var description: String { bitString }

}

extension Bitstring: Equatable {

}
