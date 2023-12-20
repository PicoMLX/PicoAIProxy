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
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong)
    var port: Int = 8081

    @Option(name: .shortAndLong)
    var location: String = ""

    @Option(name: .shortAndLong)
    var target: String = "https://api.openai.com"

    func run() throws {
        let app = HBApplication(
            configuration: .init(
                address: .hostname(self.hostname, port: self.port),
                serverName: "ProxyServer"
            )
        )
        try app.configure(self)
        try app.start()
        app.wait()
    }
}
