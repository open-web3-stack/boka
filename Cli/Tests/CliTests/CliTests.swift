import ArgumentParser
import Cli
import Foundation
import NIO
import Testing

struct CliTests {
    @Test func testCli() async throws {
        let cli = Boka()
        _ = try cli.run()
    }
}
