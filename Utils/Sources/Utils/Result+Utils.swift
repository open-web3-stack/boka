extension Result {
    public init(_ closure: () async throws(Failure) -> Success) async {
        do {
            self = try await .success(closure())
        } catch {
            self = .failure(error)
        }
    }
}
