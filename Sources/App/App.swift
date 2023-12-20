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
struct HummingbirdArguments: ParsableCommand, AppArguments {
    @Option(name: .shortAndLong)
    var hostname: String = "0.0.0.0"

    @Option(name: .shortAndLong)
    var port: Int = Int(HBEnvironment().get("port") ?? "443") ?? 443

    @Option(name: .shortAndLong)
    var organization: String = HBEnvironment().get("organization") ?? "org-0"
    
    @Option(name: .shortAndLong)
    var apiKey: String = HBEnvironment().get("apiKey") ?? "sk-0"

    @Option(name: .shortAndLong)
    var location: String = ""

    @Option(name: .shortAndLong)
    var target: String = HBEnvironment().get("target") ?? "https://api.openai.com"

    func run() throws {
        let app = HBApplication(
            configuration: .init(
                address: .hostname(self.hostname, port: self.port),
                serverName: "SwiftOpenAIProxyServer"
            )
        )
        try app.configure(self)
        try app.start()
        app.wait()
    }
}
