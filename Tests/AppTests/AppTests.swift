@testable import App
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import XCTest

final class AppTests: XCTestCase {
    struct Arguments: AppArguments {
        var hostname: String = "127.0.0.1"
        var port: Int = 0
        var location: String
        var target: String
    }

    override func setUp() {
        super.setUp()
        setenv("JWTPrivateKey", "test-key", 1)
        setenv("OpenAI-APIKey", "test-openai-key", 1)
        setenv("Anthropic-APIKey", "test-anthropic-key", 1)
        setenv("Groq-APIKey", "test-groq-key", 1)
        setenv("allowKeyPassthrough", "1", 1)
        if LLMModel.models.isEmpty {
            LLMModel.load()
        }
    }

    func createProxy(targetPort: Int) async throws -> any ApplicationProtocol {
        let args = Arguments(location: "", target: "http://127.0.0.1:\(targetPort)")
        return try await buildApplication(args)
    }

    func randomBuffer(size: Int) -> ByteBuffer {
        var data = [UInt8](repeating: 0, count: size)
        data = data.map { _ in UInt8.random(in: 0...255) }
        return ByteBufferAllocator().buffer(bytes: data)
    }

    func testSimple() async throws {
        let backendRouter = Router()
        backendRouter.get("hello") { _, _ -> String in "Hello" }
        let backendApp = Application(router: backendRouter, configuration: .init(address: .hostname("127.0.0.1", port: 0)))

        try await backendApp.test(.live) { backendClient in
            guard let backendPort = backendClient.port else {
                XCTFail("Backend port not found")
                return
            }
            let proxy = try await createProxy(targetPort: backendPort)
            try await proxy.test(.live) { client in
                try await client.execute(uri: "/hello", method: .get, headers: defaultHeaders()) { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertEqual(String(buffer: response.body), "Hello")
                }
            }
        }
    }

    func testEchoBody() async throws {
        let backendRouter = Router()
        backendRouter.post("echo") { request, context async throws -> Response in
            var request = request
            let buffer = try await request.collectBody(upTo: context.maxUploadSize)
            return Response(status: .ok, body: .init(byteBuffer: buffer))
        }
        let backendApp = Application(router: backendRouter, configuration: .init(address: .hostname("127.0.0.1", port: 0)))

        try await backendApp.test(.live) { backendClient in
            guard let backendPort = backendClient.port else {
                XCTFail("Backend port not found")
                return
            }
            let proxy = try await createProxy(targetPort: backendPort)
            try await proxy.test(.live) { client in
                let bodyString = "This is a test body"
                try await client.execute(uri: "/echo", method: .post, headers: defaultHeaders(), body: ByteBuffer(string: bodyString)) { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertEqual(String(buffer: response.body), bodyString)
                }
            }
        }
    }

    func testLargeBody() async throws {
        let backendRouter = Router()
        backendRouter.post("echo") { request, context async throws -> Response in
            var request = request
            let buffer = try await request.collectBody(upTo: context.maxUploadSize)
            return Response(status: .ok, body: .init(byteBuffer: buffer))
        }
        let backendApp = Application(router: backendRouter, configuration: .init(address: .hostname("127.0.0.1", port: 0)))

        try await backendApp.test(.live) { backendClient in
            guard let backendPort = backendClient.port else {
                XCTFail("Backend port not found")
                return
            }
            let proxy = try await createProxy(targetPort: backendPort)
            try await proxy.test(.live) { client in
                let buffer = randomBuffer(size: 1024 * 1500)
                try await client.execute(uri: "/echo", method: .post, headers: defaultHeaders(), body: buffer) { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertEqual(response.body, buffer)
                }
            }
        }
    }

    private func defaultHeaders() -> HTTPFields {
        var headers: HTTPFields = [:]
        headers[.authorization] = "Bearer sk-test-key"
        if let organizationField = HTTPField.Name("OpenAI-Organization") {
            headers[organizationField] = "org-test"
        }
        return headers
    }
}
