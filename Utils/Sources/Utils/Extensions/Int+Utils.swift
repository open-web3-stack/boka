infix operator %%

extension Int {
    public static func %% (_ left: Int, _ right: Int) -> Int {
        if left >= 0 { return left % right }
        if left >= -right { return left + right }
        return ((left % right) + right) % right
    }
}
