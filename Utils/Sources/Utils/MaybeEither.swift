public struct MaybeEither<Left, Right> {
    public var value: Either<Left, Right>

    public init(_ value: Either<Left, Right>) {
        self.value = value
    }

    public init(left value: Left) {
        self.value = .left(value)
    }

    public init(right value: Right) {
        self.value = .right(value)
    }
}

extension MaybeEither where Left == Right {
    typealias Unwrapped = Left
    public var unwrapped: Left {
        switch value {
        case let .left(left):
            left
        case let .right(right):
            right
        }
    }
}
