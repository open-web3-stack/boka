import ConsoleKit

// Set up the CLI
let input = CommandInput(arguments: CommandLine.arguments)
let console = Terminal()
let boka = Boka()
try await console.run(boka, input: input)
