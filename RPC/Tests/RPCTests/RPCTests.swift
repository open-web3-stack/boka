@testable import RPC
import Testing
import Vapor
import XCTVapor

final class RPCControllerTests: @unchecked Sendable {
    var app: Application

    init() throws {
        app = Application(.testing)

        try configure(app)
    }

    deinit {
        app.shutdown()
    }

    @Test func serviceInited() throws {
        try app.test(.GET, "health") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "true")
        }
    }
}
