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
        public typealias Request = Request3<CoreIndex, Data, [Data]>
        public typealias Response = Bool

        public static var method: String { "builder_submitWorkPackage" }
        public static var requestNames: [String] { ["coreIndex", "workPackage", "extrinsics"] }
        public static var summary: String? { "Submit a new work package for inclusion in the blockchain." }

        private let source: BuilderDataSource

        init(source: BuilderDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            let (coreIndex, workPackage, extrinsics) = request.value
            try await source.submitWorkPackage(coreIndex: coreIndex, workPackage: workPackage, extrinsics: extrinsics)
            return true
        }
    }
}
