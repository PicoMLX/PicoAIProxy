import Foundation

struct SearchProxyRequest: Decodable, Sendable {
    let provider: String?
    let query: String
    let maxResults: Int?
    let includeAnswer: Bool?
    let includeRawContent: Bool?
    let includeImages: Bool?
    let includeFavicons: Bool?
    let includeContent: Bool?
    let timeRange: String?
    let startDate: String?
    let endDate: String?
    let country: String?
    let location: String?
    let includeDomains: [String]?
    let excludeDomains: [String]?
    let raw: Bool?
    let providerOptions: [String: JSONValue]?

    static func merged(with pathProvider: String?, payload: SearchProxyRequest) -> SearchProxyRequest {
        guard let pathProvider else { return payload }
        return SearchProxyRequest(
            provider: pathProvider,
            query: payload.query,
            maxResults: payload.maxResults,
            includeAnswer: payload.includeAnswer,
            includeRawContent: payload.includeRawContent,
            includeImages: payload.includeImages,
            includeFavicons: payload.includeFavicons,
            includeContent: payload.includeContent,
            timeRange: payload.timeRange,
            startDate: payload.startDate,
            endDate: payload.endDate,
            country: payload.country,
            location: payload.location,
            includeDomains: payload.includeDomains,
            excludeDomains: payload.excludeDomains,
            raw: payload.raw,
            providerOptions: payload.providerOptions
        )
    }
}

struct SearchProxyResponse: Codable, Sendable {
    struct Result: Codable, Sendable {
        var title: String?
        var url: String?
        var snippet: String?
        var content: String?
        var publishedAt: String?
        var score: Double?
        var imageURL: String?
        var extras: [String: JSONValue]?
    }

    struct Image: Codable, Sendable {
        var url: String
        var description: String?
    }

    var provider: String
    var results: [Result]
    var answer: String?
    var images: [Image]?
    var raw: JSONValue?
    var meta: [String: JSONValue]?
}
