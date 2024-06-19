import ScaleCodec

public enum WorkResultError: Error, CaseIterable, ScaleCodec.Codable {
    case outofGas
    case panic
    case invalidCode
    case codeTooLarge // code larger than MaxServiceCodeSize
}
