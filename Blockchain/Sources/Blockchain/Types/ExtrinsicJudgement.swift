import Utils

public struct ExtrinsicJudgement {
    public typealias JudgementsList = [
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

    public var judgements: JudgementsList

    public init(
        judgements: JudgementsList
    ) {
        self.judgements = judgements
    }
}

extension ExtrinsicJudgement: Dummy {
    public static var dummy: ExtrinsicJudgement {
        ExtrinsicJudgement(judgements: [])
    }
}
