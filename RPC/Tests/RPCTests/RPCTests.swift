@testable import RPC
import Testing
import Vapor

final class RPCControllerTests: @unchecked Sendable {
    var app: Application!

    init() async throws {
        app = try await Application.make()

        let rpcController = RPCController()
        try app.register(collection: rpcController)
        try await app.execute()
    }

    @Test func serviceInited() {
        #expect(app != nil)
    }
}
