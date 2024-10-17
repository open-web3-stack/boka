import Atomics
import TracingUtils

public struct UniqueId: Sendable {
    private static let idGenerator: ManagedAtomic<Int> = ManagedAtomic(0)

    public let id: Int
    public let name: String

    public init(_ name: String) {
        id = UniqueId.idGenerator.loadThenWrappingIncrement(ordering: .relaxed)
        self.name = name
    }

    public var idString: String {
        String(id, radix: 16)
    }
}

extension UniqueId: Equatable {
    public static func == (lhs: UniqueId, rhs: UniqueId) -> Bool {
        lhs.id == rhs.id
    }
}

extension UniqueId: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension UniqueId: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        self.init(stringInterpolation.description)
    }
}

extension UniqueId: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension UniqueId: CustomStringConvertible {
    public var description: String {
        "\(name)#\(idString)"
    }
}

extension String {
    public var uniqueId: UniqueId {
        UniqueId(self)
    }
}

extension Logger {
    public init(label: UniqueId) {
        self.init(label: label.description)
    }
}
