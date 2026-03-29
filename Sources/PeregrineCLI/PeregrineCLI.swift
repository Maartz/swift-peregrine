import ArgumentParser

@main
struct PeregrineCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "peregrine",
        abstract: "The Peregrine web framework CLI",
        subcommands: [
            New.self,
            Gen.self,
            Migrate.self,
            Server.self,
            Build.self,
        ]
    )
}
