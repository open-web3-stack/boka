@testable import Blockchain
import Codec
import Foundation
import Testing
import Utils

struct WorkPackageReportTests {
    @Test
    func refinementContextOrderingAndEncodedSize() throws {
        let anchor = RefinementContext.Anchor(
            headerHash: data32(1),
            stateRoot: data32(2),
            beefyRoot: data32(3),
        )

        #expect(anchor < RefinementContext.Anchor(headerHash: data32(2), stateRoot: data32(0), beefyRoot: data32(0)))
        #expect(anchor < RefinementContext.Anchor(headerHash: data32(1), stateRoot: data32(4), beefyRoot: data32(0)))
        #expect(anchor < RefinementContext.Anchor(headerHash: data32(1), stateRoot: data32(2), beefyRoot: data32(4)))

        let lookup = RefinementContext.LookupAnchor(headerHash: data32(4), timeslot: 10)
        #expect(lookup < RefinementContext.LookupAnchor(headerHash: data32(5), timeslot: 0))
        #expect(lookup < RefinementContext.LookupAnchor(headerHash: data32(4), timeslot: 11))

        let context = RefinementContext(
            anchor: anchor,
            lookupAnchor: lookup,
            prerequisiteWorkPackages: [data32(6), data32(7)],
        )
        let laterContext = RefinementContext(
            anchor: anchor,
            lookupAnchor: RefinementContext.LookupAnchor(headerHash: data32(4), timeslot: 11),
            prerequisiteWorkPackages: [],
        )

        #expect(context < laterContext)
        let encodedContext = try JamEncoder.encode(context)
        #expect(context.encodedSize == encodedContext.count)
    }

    @Test
    func workPackageComparesByAuthorizerContextAndWorkItemCount() throws {
        let base = try makeWorkPackage(serviceIndex: 1, codeHash: data32(1), workItemCount: 1)
        let laterService = try makeWorkPackage(serviceIndex: 2, codeHash: data32(0), workItemCount: 1)
        let laterCodeHash = try makeWorkPackage(serviceIndex: 1, codeHash: data32(2), workItemCount: 1)
        let laterContext = try makeWorkPackage(
            serviceIndex: 1,
            codeHash: data32(1),
            context: makeContext(lookupTimeslot: 20),
            workItemCount: 1,
        )
        let longerWorkItems = try makeWorkPackage(serviceIndex: 1, codeHash: data32(1), workItemCount: 2)

        #expect(base < laterService)
        #expect(base < laterCodeHash)
        #expect(base < laterContext)
        #expect(base < longerWorkItems)
    }

    @Test
    func workPackageRefHashAndCodecsRoundTrip() throws {
        let config = ProtocolConfigRef.tiny
        let package = try makeWorkPackage(config: config, serviceIndex: 12, codeHash: data32(8), workItemCount: 2)
        let ref = package.asRef()

        #expect(ref.value == package)
        #expect(ref.hash == package.hash())
        let encodedPackageHash = try JamEncoder.encode(package).blake2b256hash()
        #expect(package.hash() == encodedPackageHash)

        #expect(try WorkPackage.decode(data: package.encode(), withConfig: config) == package)
        #expect(try JamDecoder.decode(WorkPackage.self, from: JamEncoder.encode(package), withConfig: config) == package)

        let encoder = JSONEncoder()
        encoder.userInfo[.config] = config
        let decoder = JSONDecoder()
        decoder.userInfo[.config] = config
        #expect(try decoder.decode(WorkPackage.self, from: encoder.encode(package)) == package)
    }

    @Test
    func workPackageAuthorizerUsesHistoricalCodePreimage() async throws {
        let codeHash = data32(9)
        let codeBlob = Data([10, 11, 12])
        let configurationBlob = Data([13, 14])
        let package = try makeWorkPackage(
            serviceIndex: 42,
            codeHash: codeHash,
            context: makeContext(lookupTimeslot: 33),
            configurationBlob: configurationBlob,
            workItemCount: 1,
        )
        let accounts = StubServiceAccounts(preimages: [
            .init(serviceAccount: 42, timeslot: 33, hash: codeHash): try encodeCodeAndMeta(codeBlob: codeBlob),
        ])

        #expect(try await package.authorizationCode(serviceAccounts: accounts) == codeBlob)
        #expect(try await package.authorizer(serviceAccounts: accounts) == Blake2b256.hash(codeBlob, configurationBlob))

        let emptyAccounts = StubServiceAccounts()
        #expect(try await package.authorizationCode(serviceAccounts: emptyAccounts) == nil)
        #expect(try await package.authorizer(serviceAccounts: emptyAccounts) == nil)
    }

    @Test
    func workReportValidationAcceptsValidReportAndRejectsInvalidBounds() throws {
        let config = ProtocolConfigRef.tiny
        let valid = WorkReport.dummy(config: config)
        try valid.validateSelf(config: config)

        var tooManyDependencies = valid
        tooManyDependencies.refinementContext.prerequisiteWorkPackages = Set(
            (0 ... config.value.maxDepsInWorkReport).map { data32(UInt8($0 + 20)) },
        )
        do {
            try tooManyDependencies.validateSelf(config: config)
            Issue.record("Expected too many dependencies")
        } catch WorkReport.WorkReportError.tooManyDependencies {
        } catch {
            Issue.record("Expected tooManyDependencies, got \(error)")
        }

        var tooBig = valid
        tooBig.authorizerTrace = Data(repeating: 1, count: config.value.maxWorkReportBlobSize + 1)
        do {
            try tooBig.validateSelf(config: config)
            Issue.record("Expected too big report")
        } catch WorkReport.WorkReportError.tooBig {
        } catch {
            Issue.record("Expected tooBig, got \(error)")
        }

        var invalidCore = valid
        invalidCore.coreIndex = UInt(config.value.totalNumberOfCores)
        do {
            try invalidCore.validateSelf(config: config)
            Issue.record("Expected invalid core index")
        } catch WorkReport.WorkReportError.invalidCoreIndex {
        } catch {
            Issue.record("Expected invalidCoreIndex, got \(error)")
        }
    }

    private func makeContext(
        lookupTimeslot: TimeslotIndex = 10,
        prerequisiteWorkPackages: Set<Data32> = [],
    ) -> RefinementContext {
        RefinementContext(
            anchor: RefinementContext.Anchor(
                headerHash: data32(1),
                stateRoot: data32(2),
                beefyRoot: data32(3),
            ),
            lookupAnchor: RefinementContext.LookupAnchor(
                headerHash: data32(4),
                timeslot: lookupTimeslot,
            ),
            prerequisiteWorkPackages: prerequisiteWorkPackages,
        )
    }

    private func makeWorkPackage(
        config: ProtocolConfigRef = .tiny,
        serviceIndex: ServiceIndex,
        codeHash: Data32,
        context: RefinementContext? = nil,
        configurationBlob: Data = Data([5, 6]),
        workItemCount: Int,
    ) throws -> WorkPackage {
        WorkPackage(
            authorizationToken: Data([7]),
            authorizationServiceIndex: serviceIndex,
            authorizationCodeHash: codeHash,
            configurationBlob: configurationBlob,
            context: context ?? makeContext(),
            workItems: try ConfigLimitedSizeArray(
                config: config,
                array: Array(repeating: WorkItem.dummy(config: config), count: workItemCount),
            ),
        )
    }

    private func encodeCodeAndMeta(codeBlob: Data) throws -> Data {
        let metadata = Metadata(
            formatVersion: 1,
            programName: Data("authorizer".utf8),
            version: Data("1.0.0".utf8),
            license: Data(),
            authors: [],
        )
        let metadataData = try JamEncoder.encode(metadata)
        var data = Data(UInt(metadataData.count).encode(method: .variableWidth))
        data.append(metadataData)
        data.append(codeBlob)
        return data
    }
}

private struct StubServiceAccounts: ServiceAccounts {
    fileprivate struct LookupKey: Hashable, Sendable {
        var serviceAccount: ServiceIndex
        var timeslot: TimeslotIndex
        var hash: Data32
    }

    var preimages: [LookupKey: Data] = [:]

    func copy() -> ServiceAccounts {
        self
    }

    func get(serviceAccount _: ServiceIndex) async throws -> ServiceAccountDetails? {
        nil
    }

    func get(serviceAccount _: ServiceIndex, storageKey _: Data) async throws -> Data? {
        nil
    }

    func get(serviceAccount _: ServiceIndex, preimageHash _: Data32) async throws -> Data? {
        nil
    }

    func get(
        serviceAccount _: ServiceIndex,
        preimageHash _: Data32,
        length _: UInt32,
    ) async throws -> StateKeys.ServiceAccountPreimageInfoKey.Value? {
        nil
    }

    func historicalLookup(
        serviceAccount index: ServiceIndex,
        timeslot: TimeslotIndex,
        preimageHash hash: Data32,
    ) async throws -> Data? {
        preimages[LookupKey(serviceAccount: index, timeslot: timeslot, hash: hash)]
    }

    mutating func set(serviceAccount _: ServiceIndex, account _: ServiceAccountDetails?) {}

    mutating func set(serviceAccount _: ServiceIndex, storageKey _: Data, value _: Data?) async throws {}

    mutating func set(serviceAccount _: ServiceIndex, preimageHash _: Data32, value _: Data?) {}

    mutating func set(
        serviceAccount _: ServiceIndex,
        preimageHash _: Data32,
        length _: UInt32,
        value _: StateKeys.ServiceAccountPreimageInfoKey.Value?,
    ) async throws {}

    mutating func remove(serviceAccount _: ServiceIndex) async throws {}
}
