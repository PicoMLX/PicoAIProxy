import ArgumentParser
import Hummingbird

@main
struct HummingbirdArguments: AsyncParsableCommand, AppArguments {
    @Option(name: .shortAndLong)
    var hostname: String = "0.0.0.0"

    @Option(name: .shortAndLong)
    var port: Int = 8080

    @Option(name: .shortAndLong)
<<<<<<< Updated upstream
    var target: String = ""  // Note: this is ignored
        
    func run() async throws {
        
        // Load models and providers
        LLMModel.load()
        
        let app = buildApplication(self)
        try await app.runService()
    }
=======
    var location: String = ""

    @Option(name: .shortAndLong)
    var target: String = ""
>>>>>>> Stashed changes

    func run() async throws {
        LLMModel.load()
        let app = try await buildApplication(self)
        try await app.runService()
    }
}
