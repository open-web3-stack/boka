import ConsoleKit

// Set up the CLI
let input = CommandInput(arguments: CommandLine.arguments)
let console = Terminal()
let boka = Boka()
do {
    try await console.run(boka, input: input)
} catch {
    console.error("\(error.localizedDescription)")
    throw error
}
