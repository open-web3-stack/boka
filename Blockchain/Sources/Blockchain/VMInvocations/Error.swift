public enum VMInvocationsError: Error {
    case serviceAccountNotFound
    case outOfGas
    case pageFault(UInt32)
}
