import Utils

public enum Constants {
    // Q: The maximum number of items in the authorizations queue.
    public enum MaxAuthorizationsQueueItems: ConstInt {
        public static var value: Int {
            80
        }
    }

    // S: The maximum size of service code in octets.
    public enum MaxServiceCodeSize: ConstInt {
        public static var value: Int {
            4_000_000
        }
    }

    // V: The total number of validators.
    public enum TotalNumberOfValidators: ConstInt {
        public static var value: Int {
            1023
        }
    }

    public enum TwoThirdValidatorsPlusOne: ConstInt {
        public static var value: Int {
            Constants.TotalNumberOfValidators.value * 2 / 3 + 1
        }
    }
}
