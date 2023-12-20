@testable import App
import Hummingbird
import HummingbirdXCT
import XCTest

final class AppTests: XCTestCase {
    func createProxy(port: Int) async throws -> HBApplication {
        struct Arguments: AppArguments {
            var location: String
            var target: String
        }
        return try await createProxy(args: Arguments(location: "", target: "http://localhost:\(port)"))
    }

    func createProxy(args: AppArguments) async throws -> HBApplication {
        let app = HBApplication(testing: .live)
        try await app.configure(args)
        return app
    }

    func randomBuffer(size: Int) -> ByteBuffer {
        var data = [UInt8](repeating: 0, count: size)
        data = data.map { _ in UInt8.random(in: 0...255) }
        return ByteBufferAllocator().buffer(bytes: data)
    }

    func testSimple() async throws {
        let app = HBApplication(configuration: .init(address: .hostname(port: 0)))
        app.router.get("hello") { _ in
            return "Hello"
        }
        try app.start()
        defer { app.stop() }

        let proxy = try await createProxy(port: app.server.port!)
        try proxy.XCTStart()
        defer { proxy.XCTStop() }

        try proxy.XCTExecute(uri: "/hello", method: .GET) { response in
            let body = try XCTUnwrap(response.body)
            XCTAssertEqual(String(buffer: body), "Hello")
        }
    }

    func testEchoBody() async throws {
        let app = HBApplication(configuration: .init(address: .hostname(port: 0)))
        app.router.post("echo") { request in
            return request.body.buffer
        }
        try app.start()
        defer { app.stop() }

        let proxy = try await createProxy(port: app.server.port!)
        try proxy.XCTStart()
        defer { proxy.XCTStop() }

        let bodyString = "This is a test body"
        try proxy.XCTExecute(uri: "/echo", method: .POST, body: ByteBuffer(string: bodyString)) { response in
            let body = try XCTUnwrap(response.body)
            XCTAssertEqual(String(buffer: body), bodyString)
        }
    }

    func testLargeBody() async throws {
        let app = HBApplication(configuration: .init(address: .hostname(port: 0)))
        app.router.post("echo") { request in
            return request.body.buffer
        }
        try app.start()
        defer { app.stop() }

        let proxy = try await createProxy(port: app.server.port!)
        try proxy.XCTStart()
        defer { proxy.XCTStop() }

        let buffer = randomBuffer(size: 1024 * 1500)
        try proxy.XCTExecute(uri: "/echo", method: .POST, body: buffer) { response in
            XCTAssertEqual(response.body, buffer)
        }
    }
}
