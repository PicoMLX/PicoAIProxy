@testable import App
import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import NIOCore
import XCTest

final class SearchProxyTests: XCTestCase {
    struct Arguments: AppArguments {
        var hostname: String = "127.0.0.1"
        var port: Int = 0
        var location: String = ""
        var target: String = "https://api.openai.com"
    }

    override func setUp() {
        super.setUp()
        setenv("JWTPrivateKey", "test-key", 1)
        setenv("OpenAI-APIKey", "test-openai-key", 1)
        setenv("Exa-APIKey", "exa-key", 1)
        setenv("Firecrawl-APIKey", "firecrawl-key", 1)
        setenv("Tavily-APIKey", "tavily-key", 1)
        setenv("allowKeyPassthrough", "1", 1)
        if LLMModel.models.isEmpty {
            LLMModel.load()
        }
    }

    override func tearDown() {
        unsetenv("Exa-APIKey")
        unsetenv("Firecrawl-APIKey")
        unsetenv("Tavily-APIKey")
        unsetenv("allowKeyPassthrough")
        super.tearDown()
    }

    func createProxyApp() async throws -> any ApplicationProtocol {
        let args = Arguments()
        return try await buildApplication(args)
    }

    func testExaSearchProxy() async throws {
        let backendRouter = Router()
        backendRouter.post("search") { request, _ async throws -> Response in
            var request = request
            let buffer = try await request.collectBody(upTo: 1024 * 1024)
            let bodyString = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes)
            let apiKeyHeader = HTTPField.Name("x-api-key")!
            XCTAssertEqual(request.headers[apiKeyHeader], "exa-key")
            XCTAssertTrue(bodyString?.contains("\"query\":\"latest ai news\"") ?? false)
            XCTAssertTrue(bodyString?.contains("numResults") ?? false)
            let responseJSON = """
            {
              "requestId": "req-123",
              "results": [
                {
                  "title": "AI Update",
                  "url": "https://example.com/ai",
                  "summary": "Summary",
                  "publishedDate": "2024-01-01T00:00:00Z"
                }
              ],
              "costDollars": {"total": 0.01}
            }
            """.data(using: .utf8)!
            var responseBuffer = ByteBufferAllocator().buffer(capacity: responseJSON.count)
            responseBuffer.writeBytes(responseJSON)
            return Response(status: .ok, body: .init(byteBuffer: responseBuffer))
        }
        let backendApp = Application(router: backendRouter, configuration: .init(address: .hostname("127.0.0.1", port: 0)))

        try await backendApp.test(.live) { backendClient in
            guard let backendPort = backendClient.port else {
                XCTFail("backend port missing")
                return
            }
            setenv("Exa-BaseURL", "http://127.0.0.1:\(backendPort)", 1)
            defer { unsetenv("Exa-BaseURL") }

            let proxy = try await createProxyApp()
            try await proxy.test(.live) { client in
                let payload = """
                {
                  "query": "latest ai news",
                  "maxResults": 5,
                  "includeContent": true
                }
                """
                try await client.execute(
                    uri: "/search/exa",
                    method: .post,
                    headers: defaultHeaders(),
                    body: ByteBuffer(string: payload)
                ) { response in
                    XCTAssertEqual(response.status, .ok)
                    let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                    XCTAssertEqual(json?["provider"] as? String, "exa")
                    let results = json?["results"] as? [[String: Any]]
                    XCTAssertEqual(results?.first?["title"] as? String, "AI Update")
                    let meta = json?["meta"] as? [String: Any]
                    XCTAssertEqual(meta?["cost"] as? Double, 0.01)
                }
            }
        }
    }

    func testFirecrawlSearchProxyIncludesImages() async throws {
        let backendRouter = Router()
        backendRouter.post("search") { request, _ async throws -> Response in
            XCTAssertEqual(request.headers[.authorization], "Bearer firecrawl-key")
            let responseJSON = """
            {
              "success": true,
              "data": {
                "web": [
                  {"title": "Result", "description": "Desc", "url": "https://example.com", "markdown": "# md"}
                ],
                "images": [
                  {"imageUrl": "https://example.com/img.png", "title": "Image"}
                ]
              }
            }
            """.data(using: .utf8)!
            var responseBuffer = ByteBufferAllocator().buffer(capacity: responseJSON.count)
            responseBuffer.writeBytes(responseJSON)
            return Response(status: .ok, body: .init(byteBuffer: responseBuffer))
        }
        let backendApp = Application(router: backendRouter, configuration: .init(address: .hostname("127.0.0.1", port: 0)))

        try await backendApp.test(.live) { backendClient in
            guard let port = backendClient.port else {
                XCTFail("backend port missing")
                return
            }
            setenv("Firecrawl-BaseURL", "http://127.0.0.1:\(port)", 1)
            defer { unsetenv("Firecrawl-BaseURL") }

            let proxy = try await createProxyApp()
            try await proxy.test(.live) { client in
                let payload = """
                {
                  "query": "firecrawl",
                  "maxResults": 3,
                  "includeImages": true,
                  "includeContent": true
                }
                """
                try await client.execute(
                    uri: "/search/firecrawl",
                    method: .post,
                    headers: defaultHeaders(),
                    body: ByteBuffer(string: payload)
                ) { response in
                    XCTAssertEqual(response.status, .ok)
                    let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                    let results = json?["results"] as? [[String: Any]]
                    XCTAssertEqual(results?.count, 1)
                    let images = json?["images"] as? [[String: Any]]
                    XCTAssertEqual(images?.first?["url"] as? String, "https://example.com/img.png")
                }
            }
        }
    }

    func testTavilySearchProxy() async throws {
        let backendRouter = Router()
        backendRouter.post("search") { request, _ async throws -> Response in
            XCTAssertEqual(request.headers[.authorization], "Bearer tavily-key")
            let responseJSON = """
            {
              "query": "who is leo messi?",
              "answer": "Lionel Messi is...",
              "images": [],
              "results": [
                {"title": "Messi", "url": "https://example.com", "content": "content", "score": 0.9, "raw_content": "raw"}
              ],
              "auto_parameters": {"topic": "general"},
              "response_time": "1.0",
              "request_id": "req-1"
            }
            """.data(using: .utf8)!
            var responseBuffer = ByteBufferAllocator().buffer(capacity: responseJSON.count)
            responseBuffer.writeBytes(responseJSON)
            return Response(status: .ok, body: .init(byteBuffer: responseBuffer))
        }
        let backendApp = Application(router: backendRouter, configuration: .init(address: .hostname("127.0.0.1", port: 0)))

        try await backendApp.test(.live) { backendClient in
            guard let port = backendClient.port else {
                XCTFail("backend port missing")
                return
            }
            setenv("Tavily-BaseURL", "http://127.0.0.1:\(port)", 1)
            defer { unsetenv("Tavily-BaseURL") }

            let proxy = try await createProxyApp()
            try await proxy.test(.live) { client in
                let payload = """
                {
                  "query": "who is leo messi?",
                  "maxResults": 1,
                  "includeAnswer": true,
                  "includeRawContent": true,
                  "raw": true
                }
                """
                try await client.execute(
                    uri: "/search/tavily",
                    method: .post,
                    headers: defaultHeaders(),
                    body: ByteBuffer(string: payload)
                ) { response in
                    XCTAssertEqual(response.status, .ok)
                    let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                    XCTAssertEqual(json?["provider"] as? String, "tavily")
                    XCTAssertEqual(json?["answer"] as? String, "Lionel Messi is...")
                    let meta = json?["meta"] as? [String: Any]
                    XCTAssertEqual(meta?["requestId"] as? String, "req-1")
                    XCTAssertNotNil(json?["raw"])
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
