public enum WorkResultError: Error, CaseIterable, Codable {
    case outofGas
    case panic
    case invalidCode
    case codeTooLarge // code larger than MaxServiceCodeSize
}
