import ArgumentParser

struct Gen: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gen",
        abstract: "Code generators",
        subcommands: [
            GenSchema.self,
            GenJSON.self,
            GenHTML.self,
        ]
    )
}
