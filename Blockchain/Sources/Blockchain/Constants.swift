import Utils

public enum Constants {
    public enum Zero: ConstInt {
        public static var value: Int {
            0
        }
    }

    public enum One: ConstInt {
        public static var value: Int {
            1
        }
    }

    public enum IntMax: ConstInt {
        public static var value: Int {
            Int.max
        }
    }

    // C: The total number of cores.
    public enum TotalNumberOfCores: ConstInt {
        public static var value: Int {
            341
        }
    }

    // E: The length of an epoch in timeslots.
    public enum EpochLength: ConstInt {
        public static var value: Int {
            600
        }
    }

    // N: The number of ticket entries per validator.
    public enum ValidatorTicketEntriesCount: ConstInt {
        public static var value: Int {
            2
        }
    }

    // O: The maximum number of items in the authorizations pool.
    public enum MaxAuthorizationsPoolItems: ConstInt {
        public static var value: Int {
            8
        }
    }

    // V: The total number of validators.
    public enum TotalNumberOfValidators: ConstInt {
        public static var value: Int {
            1023
        }
    }
}
