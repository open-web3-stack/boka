extension FixedWidthInteger {
    /// Return the next power of two that is equal or greater than self.
    /// Returns nil if self is 0 or the next power of two is greater than `Self.max`.
    public var nextPowerOfTwo: Self? {
        guard self > 0 else { return nil }
        let leadingZeroBitCount = (self - 1).leadingZeroBitCount
        guard leadingZeroBitCount > 0 else { return nil }
        return 1 << (bitWidth - leadingZeroBitCount)
    }
}
