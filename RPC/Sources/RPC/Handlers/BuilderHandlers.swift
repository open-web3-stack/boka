import Blockchain
import Codec
import Foundation
import Utils

public enum BuilderHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        SubmitWorkPackage.self,
    ]

    public static func getHandlers(source: BuilderDataSource) -> [any RPCHandler] {
        [
            SubmitWorkPackage(source: source),
        ]
    }

    public struct SubmitWorkPackage: RPCHandler {
        public typealias Request = Request1<Data>
        public typealias Response = Bool

        public static var method: String { "builder_submitWorkPackage" }
        public static var requestNames: [String] { ["workPackage"] }
        public static var summary: String? { "Send the work package to other connected nodes" }

        private let source: BuilderDataSource

        init(source: BuilderDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            try await source.submitWorkPackage(data: request.value)
        }
    }
}
