public struct Block {
  public private(set) var header: Header
  public private(set) var extrinsic: Extrinsic

  public init(header: Header, extrinsic: Extrinsic) {
    self.header = header
    self.extrinsic = extrinsic
  }
}
