import bls
import Foundation
import Testing

@testable import Utils

final class MiddlewareTests {
    actor OrderManager {
        private(set) var order: [Int] = []

        func appendOrder(_ value: Int) {
            order.append(value)
        }
    }

    @Test func testParallelDispatcher() async throws {
        let orderManager = OrderManager()

        let firstMiddleware = Middleware.noop
        let secondMiddleware = Middleware.noop

        let parallelMiddleware = Middleware.parallel(firstMiddleware, secondMiddleware)

        let handler: MiddlewareHandler<Void> = { _ in
            await orderManager.appendOrder(2)
        }

        try await parallelMiddleware.handle((), next: {
            await orderManager.appendOrder(1)
        })

        let order = await orderManager.order
        #expect(order.count == 2)
    }

    @Test func testSerialDispatcher() async throws {
        let orderManager = OrderManager()

        let firstMiddleware = Middleware.noop
        let secondMiddleware = Middleware.noop

        let serialMiddleware = Middleware.serial(firstMiddleware, secondMiddleware)

        let handler: MiddlewareHandler<Void> = { _ in
            await orderManager.appendOrder(2)
        }

        try await serialMiddleware.handle((), next: {
            await orderManager.appendOrder(1)
            try await handler(())
        })

        let order = await orderManager.order
        #expect(order == [1, 2])
    }

    @Test func testMiddlewareChain() async throws {
        let orderManager = OrderManager()

        let middleware1 = Middleware.noop
        let middleware2 = Middleware.noop

        let middlewareChain = Middleware.serial(middleware1, middleware2)

        let handler: MiddlewareHandler<Void> = { _ in
            await orderManager.appendOrder(2)
        }

        try await middlewareChain.handle((), next: {
            await orderManager.appendOrder(1)
            try await handler(())
        })

        let order = await orderManager.order
        #expect(order == [1, 2])
    }
}
