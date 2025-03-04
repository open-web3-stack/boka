import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct CoreAuthorizer: Codable {
    var core: CoreIndex
    var auth: Data32
}

struct AuthorizationsInput: Codable {
    var slot: TimeslotIndex
    var auths: [CoreAuthorizer]
}

struct AuthorizationsState: Equatable, Codable, Authorization {
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<
            Data32,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxAuthorizationsPoolItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >

    var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >

    mutating func mergeWith(postState: AuthorizationPostState) {
        coreAuthorizationPool = postState.coreAuthorizationPool
    }
}

struct AuthorizationsTestcase: Codable {
    var input: AuthorizationsInput
    var preState: AuthorizationsState
    var postState: AuthorizationsState
}

struct AuthorizationsTests {
    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "authorizations/\(variant)", extension: "bin")
    }

    func authorizationsTests(_ testcase: Testcase, variant: TestVariants) throws {
        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(AuthorizationsTestcase.self)

        var state = testcase.preState
        let result = try state.update(
            config: config,
            timeslot: testcase.input.slot,
            auths: testcase.input.auths.map { ($0.core, $0.auth) }
        )

        state.mergeWith(postState: result)

        #expect(state == testcase.postState)
    }

    @Test(arguments: try AuthorizationsTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        try authorizationsTests(testcase, variant: .tiny)
    }

    @Test(arguments: try AuthorizationsTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) throws {
        try authorizationsTests(testcase, variant: .full)
    }
}
