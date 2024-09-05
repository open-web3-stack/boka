@testable import Blockchain
import Testing

// @retroactive to slient Equtable warning
extension ValidateError: @retroactive Equatable {
    public static func == (lhs: ValidateError, rhs: ValidateError) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}

enum ChildError: Error {
    case badValue(Int)
}

struct Child: Validate {
    typealias Config = Int

    var value: Int

    func validate(config: Config) throws {
        if value < config {
            throw ChildError.badValue(value)
        }
    }
}

struct Parent: Validate {
    typealias Config = Int

    var child: Child
    var child2: Child
}

struct ValidateTests {
    @Test func validate() throws {
        var parent = Parent(child: Child(value: 1), child2: Child(value: 5))
        try parent.validate(config: 0)
        #expect(throws: ValidateError.childError(field: "child", error: ChildError.badValue(1))) {
            try parent.validate(config: 5)
        }

        parent.child.value = 10

        #expect(throws: ValidateError.childError(field: "child2", error: ChildError.badValue(5))) {
            try parent.validate(config: 10)
        }
    }
}
