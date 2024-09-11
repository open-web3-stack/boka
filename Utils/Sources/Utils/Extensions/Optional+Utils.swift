public enum OptionalError: Swift.Error {
    case nilValue
}

extension Optional {
    public func unwrap() throws -> Wrapped {
        guard let self else {
            throw OptionalError.nilValue
        }
        return self
    }

    public func unwrap<E: Error>(orError: @autoclosure () -> E) throws(E) -> Wrapped {
        guard let self else {
            throw orError()
        }
        return self
    }
}
