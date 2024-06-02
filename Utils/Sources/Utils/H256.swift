import Foundation

public struct H256 {
  static public var zero: H256 = H256(Data(repeating: 0, count: 32))!

  public private(set) var data: Data

  public init?(_ value: Data) {
    guard value.count == 32 else {
      return nil
    }
    self.data = value
  }
}

extension H256: Equatable, Hashable {}

extension H256: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    return "0x\(data.map { String(format: "%02x", $0) }.joined())"
  }

  public var debugDescription: String {
    return description
  }
}


