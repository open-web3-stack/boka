struct SystemHandler {
    static func getHandlers() -> [String: JSONRPCHandler] {
        let handler = SystemHandler()

        return [
            "system_health": handler.health,
            "system_name": handler.name,
        ]
    }

    func health(request _: JSONRequest) async throws -> any Encodable {
        true
    }

    func name(request _: JSONRequest) async throws -> any Encodable {
        "Boka"
    }
}
