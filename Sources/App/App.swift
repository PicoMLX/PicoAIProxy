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
    var location: String = ""

    @Option(name: .shortAndLong)
    var target: String = "https://api.openai.com"

    func run() async throws {
        let app = HBApplication(
            configuration: .init(
                address: .hostname(self.hostname, port: port),
                serverName: "SwiftOpenAIProxyServer"
            )
        )
        if let port = HBEnvironment().get("PORT") {
            app.logger.info("Env var port is \(port)")
        }
        try await app.configure(self)
        try app.start()
        await app.asyncWait()
    }
}
