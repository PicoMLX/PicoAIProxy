//
//  App.swift
//
//
//  Created by Ronald Mannak on 12/19/23.
//
//  Based on https://opticalaberration.com/2021/12/proxy-server.html

import ArgumentParser
import Hummingbird

@main
struct HummingbirdArguments: AsyncParsableCommand, AppArguments {
    @Option(name: .shortAndLong)
    var hostname: String = "0.0.0.0"

    @Option(name: .shortAndLong)
        var port: Int = 8080
    
    @Option(name: .shortAndLong)
    var location: String = "" // Note: this is ignored

    @Option(name: .shortAndLong)
    var target: String = ""  // Note: this is ignored

    func run() async throws {
        
        // Load models and providers
        LLMModel.load()
        
        // Use Railway.app's port
        let port = Int(HBEnvironment().get("PORT") ?? "8080") ?? 8080
        let app = HBApplication(
            configuration: .init(
                address: .hostname(self.hostname, port: port),
                serverName: "SwiftOpenAIProxyServer"
            )
        )
        try await app.configure(self)
        try app.start()
        await app.asyncWait()
    }
}
