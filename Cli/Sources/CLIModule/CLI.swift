// Sources/CLIModule/CLI.swift

import ArgumentParser

public struct Boka: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "A command-line tool for boka.",
        subcommands: [BasePath.self, Chain.self, ConfigFile.self, Help.self],
        helpNames: [.short, .long]
    )

    public init() {}

    public func run() throws {
        print(Boka.helpMessage())
    }
}

extension Boka {
    public struct BasePath: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "base-path",
            abstract: "Base path to database files.",
            aliases: ["d"]
        )

        @Argument(help: "Path to the database files.")
        var path: String

        public init() {}

        public func run() throws {
            print("Base path set to: \(path)")
        }
    }

    public struct Chain: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "chain",
            abstract: "Path to chain spec file.",
            aliases: ["c"]
        )

        @Argument(help: "Path to the chain spec file.")
        var path: String

        public init() {}

        public func run() throws {
            print("Chain spec file path set to: \(path)")
        }
    }

    public struct ConfigFile: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "config-file",
            abstract: "Path to config file.",
            aliases: ["f"]
        )

        @Argument(help: "Path to the config file.")
        public var path: String

        public init() {}

        public func run() throws {
            print("Config file path set to: \(path)")
        }
    }

    public struct Help: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "help",
            abstract: "Print help message.",
            aliases: ["h"]
        )

        @Argument(help: "Subcommand to get help for.")
        var subcommand: String?

        public init() {}

        public func run() throws {
            if let subcommand {
                switch subcommand {
                case "base-path", "d":
                    print(BasePath.helpMessage())
                case "chain", "c":
                    print(Chain.helpMessage())
                case "config-file", "f":
                    print(ConfigFile.helpMessage())
                default:
                    print("Unknown subcommand: \(subcommand)")
                }
            } else {
                print(Boka.helpMessage())
            }
        }
    }
}
