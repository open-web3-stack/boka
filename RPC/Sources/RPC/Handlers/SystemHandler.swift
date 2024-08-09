struct SystemHandler {
    static func getHandlers() -> [String: JSONRPCHandler] {
        let handler = SystemHandler()

        return [
            "system_health": handler.health,
        ]
    }

    func health(request _: JSONRequest) async throws -> any Encodable {
        true
    }
}
