import AsyncHTTPClient
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Hummingbird
import HTTPTypes

struct SearchProvider: Sendable {
    enum AuthStrategy: Sendable {
        case bearer
        case header(name: String)
    }

    struct ProviderResponse {
        let status: HTTPResponse.Status
        let headers: HTTPFields
        let body: Data
    }

    let slug: String
    let apiKeyEnv: String
    let baseURLEnv: String?
    let defaultBaseURL: String
    let path: String
    let authStrategy: AuthStrategy
    let buildBody: @Sendable (SearchProxyRequest) throws -> JSONValue
    let normalize: @Sendable (ProviderResponse, SearchProxyRequest) throws -> SearchProxyResponse

    func makeRequest(from proxyRequest: SearchProxyRequest, environment: Environment) throws -> HTTPClientRequest {
        guard let apiKey = environment.get(apiKeyEnv) else {
            throw HTTPError(.internalServerError, message: "Missing API key for provider \(slug)")
        }

        let baseURL: String
        if let overrideKey = baseURLEnv, let override = environment.get(overrideKey), !override.isEmpty {
            baseURL = override
        } else {
            baseURL = defaultBaseURL
        }
        guard let url = URL(string: baseURL)?.appendingPathComponent(path) else {
            throw HTTPError(.internalServerError, message: "Invalid base URL for provider \(slug)")
        }

        let bodyValue = try buildBody(proxyRequest)
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(bodyValue)

        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        switch authStrategy {
        case .bearer:
            request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        case .header(let name):
            request.headers.add(name: name, value: apiKey)
        }
        request.body = .bytes(bodyData)
        return request
    }

    func normalizeResponse(_ response: HTTPClientResponse, body: Data, request: SearchProxyRequest) throws -> SearchProxyResponse {
        let status = HTTPResponse.Status(code: Int(response.status.code), reasonPhrase: response.status.reasonPhrase)
        let providerResponse = ProviderResponse(status: status, headers: HTTPFields(response.headers, splitCookie: false), body: body)
        return try normalize(providerResponse, request)
    }
}

enum SearchProviders {
    static let exa = SearchProvider(
        slug: "exa",
        apiKeyEnv: "Exa-APIKey",
        baseURLEnv: "Exa-BaseURL",
        defaultBaseURL: "https://api.exa.ai",
        path: "/search",
        authStrategy: .header(name: "x-api-key"),
        buildBody: { request in
            var payload: [String: JSONValue] = [
                "query": .string(request.query)
            ]
            if let max = request.maxResults {
                payload["numResults"] = .number(Double(max))
            }
            if let include = request.includeDomains, !include.isEmpty {
                payload["includeDomains"] = .array(include.map(JSONValue.string))
            }
            if let exclude = request.excludeDomains, !exclude.isEmpty {
                payload["excludeDomains"] = .array(exclude.map(JSONValue.string))
            }
            if let start = request.startDate {
                payload["startPublishedDate"] = .string(start)
            }
            if let end = request.endDate {
                payload["endPublishedDate"] = .string(end)
            }
            if let country = request.country {
                payload["userLocation"] = .string(country)
            }
            if request.includeContent == true {
                payload["contents"] = .object(["text": .bool(true)])
            }
            if let providerOptions = request.providerOptions {
                for (key, value) in providerOptions {
                    payload[key] = value
                }
            }
            return .object(payload)
        },
        normalize: { providerResponse, request in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ExaSearchResponse.self, from: providerResponse.body)
            var results: [SearchProxyResponse.Result] = []
            for item in response.results {
                let snippet = item.summary ?? item.highlights?.joined(separator: " \n")
                results.append(
                    SearchProxyResponse.Result(
                        title: item.title,
                        url: item.url,
                        snippet: snippet,
                        content: request.includeContent == true ? item.text : nil,
                        publishedAt: item.publishedDate,
                        score: nil,
                        imageURL: item.image,
                        extras: nil
                    )
                )
            }
            var meta: [String: JSONValue] = [:]
            if let requestId = response.requestId {
                meta["requestId"] = .string(requestId)
            }
            if let cost = response.costDollars?.total {
                meta["cost"] = .number(cost)
            }
            let raw = request.raw == true ? try JSONDecoder().decode(JSONValue.self, from: providerResponse.body) : nil
            return SearchProxyResponse(provider: "exa", results: results, answer: nil, images: nil, raw: raw, meta: meta.isEmpty ? nil : meta)
        }
    )

    static let firecrawl = SearchProvider(
        slug: "firecrawl",
        apiKeyEnv: "Firecrawl-APIKey",
        baseURLEnv: "Firecrawl-BaseURL",
        defaultBaseURL: "https://api.firecrawl.dev/v2",
        path: "/search",
        authStrategy: .bearer,
        buildBody: { request in
            var payload: [String: JSONValue] = [
                "query": .string(request.query)
            ]
            if let max = request.maxResults {
                payload["limit"] = .number(Double(max))
            }
            if let country = request.country {
                payload["country"] = .string(country)
            }
            if let location = request.location {
                payload["location"] = .string(location)
            }
            payload["sources"] = .array([.string("web")])
            if request.includeContent == true {
                payload["scrapeOptions"] = .object(["formats": .array([.string("markdown")]), "onlyMainContent": .bool(true)])
            }
            if request.includeImages == true {
                payload["sources"] = .array([.string("web"), .string("images")])
            }
            if let providerOptions = request.providerOptions {
                for (key, value) in providerOptions {
                    payload[key] = value
                }
            }
            return .object(payload)
        },
        normalize: { providerResponse, request in
            let decoder = JSONDecoder()
            let response = try decoder.decode(FirecrawlSearchResponse.self, from: providerResponse.body)
            var results: [SearchProxyResponse.Result] = []
            if let web = response.data?.web {
                for entry in web {
                    results.append(
                        SearchProxyResponse.Result(
                            title: entry.title,
                            url: entry.url,
                            snippet: entry.description,
                            content: request.includeContent == true ? entry.markdown ?? entry.html : nil,
                            publishedAt: nil,
                            score: nil,
                            imageURL: nil,
                            extras: nil
                        )
                    )
                }
            }
            var images: [SearchProxyResponse.Image]? = nil
            if request.includeImages == true, let imageEntries = response.data?.images {
                images = imageEntries.compactMap { entry in
                    guard let url = entry.imageUrl ?? entry.url else { return nil }
                    return SearchProxyResponse.Image(url: url, description: entry.title)
                }
            }
            let raw = request.raw == true ? try JSONDecoder().decode(JSONValue.self, from: providerResponse.body) : nil
            return SearchProxyResponse(provider: "firecrawl", results: results, answer: nil, images: images, raw: raw, meta: response.warning.map { ["warning": .string($0)] })
        }
    )

    static let tavily = SearchProvider(
        slug: "tavily",
        apiKeyEnv: "Tavily-APIKey",
        baseURLEnv: "Tavily-BaseURL",
        defaultBaseURL: "https://api.tavily.com",
        path: "/search",
        authStrategy: .bearer,
        buildBody: { request in
            var payload: [String: JSONValue] = [
                "query": .string(request.query)
            ]
            if let max = request.maxResults {
                payload["max_results"] = .number(Double(max))
            }
            if let includeAnswer = request.includeAnswer {
                payload["include_answer"] = includeAnswer ? .bool(true) : .bool(false)
            }
            if let includeRaw = request.includeRawContent {
                payload["include_raw_content"] = includeRaw ? .string("markdown") : .bool(false)
            } else if request.includeContent == true {
                payload["include_raw_content"] = .string("markdown")
            }
            if let includeImages = request.includeImages {
                payload["include_images"] = .bool(includeImages)
            }
            if let includeFavicons = request.includeFavicons {
                payload["include_favicon"] = .bool(includeFavicons)
            }
            if let timeRange = request.timeRange {
                payload["time_range"] = .string(timeRange)
            }
            if let start = request.startDate {
                payload["start_date"] = .string(start)
            }
            if let end = request.endDate {
                payload["end_date"] = .string(end)
            }
            if let includeDomains = request.includeDomains, !includeDomains.isEmpty {
                payload["include_domains"] = .array(includeDomains.map(JSONValue.string))
            }
            if let excludeDomains = request.excludeDomains, !excludeDomains.isEmpty {
                payload["exclude_domains"] = .array(excludeDomains.map(JSONValue.string))
            }
            if let country = request.country {
                payload["country"] = .string(country)
            }
            if let providerOptions = request.providerOptions {
                for (key, value) in providerOptions {
                    payload[key] = value
                }
            }
            return .object(payload)
        },
        normalize: { providerResponse, request in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(TavilySearchResponse.self, from: providerResponse.body)
            let results: [SearchProxyResponse.Result] = response.results.map { item in
                SearchProxyResponse.Result(
                    title: item.title,
                    url: item.url,
                    snippet: item.content,
                    content: request.includeContent == true || request.includeRawContent == true ? item.rawContent : nil,
                    publishedAt: nil,
                    score: item.score,
                    imageURL: request.includeImages == true ? response.images.first?.url : nil,
                    extras: nil
                )
            }
            let images: [SearchProxyResponse.Image]? = request.includeImages == true ? response.images.map { SearchProxyResponse.Image(url: $0.url, description: $0.description) } : nil
            var meta: [String: JSONValue] = [
                "responseTime": .string(response.responseTime),
                "requestId": .string(response.requestId)
            ]
            if let auto = response.autoParameters {
                let autoObject = auto.reduce(into: [String: JSONValue]()) { partial, item in
                    partial[item.key] = .string(item.value)
                }
                meta["autoParameters"] = .object(autoObject)
            }
            let raw = request.raw == true ? try JSONDecoder().decode(JSONValue.self, from: providerResponse.body) : nil
            return SearchProxyResponse(provider: "tavily", results: results, answer: request.includeAnswer == true ? response.answer : nil, images: images, raw: raw, meta: meta)
        }
    )

    static let all: [String: SearchProvider] = {
        let providers = [exa, firecrawl, tavily]
        return Dictionary(uniqueKeysWithValues: providers.map { ($0.slug, $0) })
    }()
}

// MARK: - Provider-specific response DTOs

private struct ExaSearchResponse: Decodable {
    struct Result: Decodable {
        let title: String?
        let url: String?
        let publishedDate: String?
        let author: String?
        let text: String?
        let highlights: [String]?
        let summary: String?
        let image: String?
    }

    struct Cost: Decodable {
        let total: Double?
    }

    let requestId: String?
    let results: [Result]
    let costDollars: Cost?
}

private struct FirecrawlSearchResponse: Decodable {
    struct WebResult: Decodable {
        let title: String?
        let description: String?
        let url: String?
        let markdown: String?
        let html: String?
    }

    struct ImageResult: Decodable {
        let title: String?
        let imageUrl: String?
        let url: String?
    }

    struct DataContainer: Decodable {
        let web: [WebResult]?
        let images: [ImageResult]?
    }

    let success: Bool
    let data: DataContainer?
    let warning: String?
}

private struct TavilySearchResponse: Decodable {
    struct Result: Decodable {
        let title: String?
        let url: String?
        let content: String?
        let score: Double?
        let rawContent: String?
    }

    struct Image: Decodable {
        let url: String
        let description: String?
    }

    let query: String
    let answer: String?
    let images: [Image]
    let results: [Result]
    let autoParameters: [String: String]?
    let responseTime: String
    let requestId: String
}
