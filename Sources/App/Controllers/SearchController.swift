import AsyncHTTPClient
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Hummingbird
import HTTPTypes
import NIOCore

struct SearchController {
    let httpClient: HTTPClient

    func registerRoutes(on router: Router<ProxyRequestContext>) {
        let group = router.group("search")
        group.post(use: handleSearch)
        group.post(":provider", use: handleSearch)
    }

    @Sendable
    private func handleSearch(_ request: Request, context: ProxyRequestContext) async throws -> Response {
        var request = request
        let buffer = try await request.collectBody(upTo: context.maxUploadSize)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else {
            throw HTTPError(.badRequest)
        }
        let payload = try decoder.decode(SearchProxyRequest.self, from: Data(bytes))
        let providerSlug = context.parameters.get("provider") ?? payload.provider
        guard let providerSlug, let provider = SearchProviders.all[providerSlug.lowercased()] else {
            throw HTTPError(.badRequest, message: "Unknown provider")
        }

        let mergedRequest = SearchProxyRequest.merged(with: providerSlug, payload: payload)
        let environment = Environment()
        context.logger.info("Search request routed to provider \(provider.slug)")
        let upstreamRequest = try provider.makeRequest(from: mergedRequest, environment: environment)

        var upstreamResponse: HTTPClientResponse
        do {
            upstreamResponse = try await httpClient.execute(upstreamRequest, timeout: .seconds(60))
        } catch {
            context.logger.error("Search proxy error: \(error.localizedDescription)")
            throw HTTPError(.badGateway, message: "Upstream request failed")
        }

        let collectedBody = try await upstreamResponse.body.collect(upTo: 1024 * 1024)
        let responseData = Data(buffer: collectedBody)

        guard (200..<300).contains(upstreamResponse.status.code) else {
            context.logger.error("Search provider \(provider.slug) returned status \(upstreamResponse.status.code)")
            throw HTTPError(HTTPResponse.Status(code: Int(upstreamResponse.status.code), reasonPhrase: upstreamResponse.status.reasonPhrase))
        }

        let normalized: SearchProxyResponse
        do {
            normalized = try provider.normalizeResponse(upstreamResponse, body: responseData, request: mergedRequest)
        } catch {
            context.logger.error("Search normalization failed: \(error.localizedDescription)")
            throw error
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let responseJSON = try encoder.encode(normalized)

        var responseHeaders = HTTPFields()
        responseHeaders[.contentType] = "application/json"
        var responseBuffer = ByteBufferAllocator().buffer(capacity: responseJSON.count)
        responseBuffer.writeBytes(responseJSON)
        return Response(status: .ok, headers: responseHeaders, body: .init(byteBuffer: responseBuffer))
    }
}
