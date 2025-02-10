#if os(WASI)
public typealias Gas = UInt64
public typealias GasInt = Int64
public typealias Balance = UInt64
#else
public typealias Gas = SaturatingNumber<UInt64>
public typealias GasInt = SaturatingNumber<Int64>
public typealias Balance = SaturatingNumber<UInt64>
extension Gas {
    public init(_ gasInt: GasInt) {
        self = .init(gasInt.value)
    }
}

extension GasInt {
    public init(_ gas: Gas) {
        self = .init(gas.value)
    }
}
#endif
