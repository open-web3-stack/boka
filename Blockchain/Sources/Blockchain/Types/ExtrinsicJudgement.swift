import Utils

public struct ExtrinsicJudgement {
    public var judgements: [
        (
            reportHash: H256,
            signatures: FixedSizeArray<
                (
                    isValid: Bool,
                    validatorIndex: ValidatorIndex,
                    signature: BandersnatchSignature
                ),
                Constants.TwoThirdValidatorsPlusOne
            >
        )
    ]
}
