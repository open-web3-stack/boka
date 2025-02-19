public enum VMInvocationsError: Error {
    case serviceAccountNotFound
    case checkMaxDepthLimit
    case checkIndexTooSmall
    case forceHalt
    case panic
}
