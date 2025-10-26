import ArgumentParser

@main
struct HummingbirdArguments: AsyncParsableCommand, AppArguments {
    @Option(name: .shortAndLong)
    var hostname: String = "0.0.0.0"

    @Option(name: .shortAndLong)
    var port: Int = 8080

    @Option(name: .shortAndLong)
    var location: String = ""

    @Option(name: .shortAndLong)
    var target: String = ""

    func run() async throws {
        LLMModel.load()
        let app = try await buildApplication(self)
        try await app.runService()
    }
}
