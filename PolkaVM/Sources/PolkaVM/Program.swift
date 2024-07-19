import Foundation

public class Program {
    public let blob: Data

    public init(blob: Data) {
        self.blob = blob
    }
}

extension Program: Equatable {
    public static func == (lhs: Program, rhs: Program) -> Bool {
        lhs.blob == rhs.blob
    }
}
