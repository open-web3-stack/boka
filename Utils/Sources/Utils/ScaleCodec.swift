import ScaleCodec

extension CustomDecoderFactory where T: ArrayInitializable {
    public static func array(
        _ decodeItem: @escaping (inout D) throws -> T.IElement
    ) -> CustomDecoderFactory {
        CustomDecoderFactory { decoder in
            var array: [T.IElement] = []
            let size = try decoder.decode(UInt32.self, .compact)
            array.reserveCapacity(Int(size))
            for _ in 0 ..< size {
                try array.append(decodeItem(&decoder))
            }
            return T(array: array)
        }
    }
}
