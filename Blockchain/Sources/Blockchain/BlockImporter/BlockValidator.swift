public enum BlockValidationError: Error {
    case invalid
    case future
}

public protocol BlockValidator {
    func validate(block: PendingBlock, chain: Blockchain) async -> Result<StateRef, BlockValidationError>
}
