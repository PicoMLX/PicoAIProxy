//
//  LLMProvider.swift
//  
//
//  Created by Ronald Mannak on 4/8/24.
//

import Foundation
import Hummingbird
import HTTPTypes

struct LLMProvider: Codable {

    /// Slug used in request paths, eg `openai`, `groq`
    let slug: String

    /// The human readable provider name, eg `OpenAI`
    let name: String

    /// Default upstream host, eg `https://api.openai.com`
    let host: String

    /// Optional environment variable that overrides the upstream host
    let hostEnvKey: String?

    /// Optional default path prefix to prepend when normalising provider paths, eg `/openai/v1`
    let pathPrefix: String?

    /// Environment variable containing the API key
    let apiEnvKey: String

    /// Header name used for the API key
    let apiHeaderKey: String

    /// Whether the API key header should be prefixed with `Bearer`
    let bearer: Bool

    /// Optional environment variable containing the organisation identifier
    let orgEnvKey: String?

    /// Header that should carry the organisation identifier (defaults to `orgEnvKey` when `nil`)
    let orgHeaderKey: String?

    /// Any additional headers that should be attached to outbound requests
    let additionalHeaders: [String: String]?
}

extension LLMProvider {

    /// Header used to communicate the selected provider between middleware components
    static let providerHeaderName = "x-llm-provider"

    static let providerHeaderField: HTTPField.Name = {
        guard let name = HTTPField.Name(providerHeaderName) else {
            fatalError("Unable to create provider header name")
        }
        return name
    }()

    private static let modelHeader: HTTPField.Name = {
        guard let name = HTTPField.Name("model") else {
            fatalError("Unable to create model header name")
        }
        return name
    }()

    /// Lookup an LLM provider by slug.
    static func provider(for slug: String) -> LLMProvider? {
        let key = slug.lowercased()
        return providersDictionary[key]
    }

    /// Updates headers with API key, org and/or other required headers for this provider
    /// - Parameter headers: headers
    func setHeaders(fields: inout HTTPFields) throws {
        let environment = Environment()

        guard let apiKey = environment.get(apiEnvKey) else {
            throw HTTPError(.internalServerError, message: "Environment API Key \(apiEnvKey) not set")
        }

        try set(value: bearer ? "Bearer \(apiKey)" : apiKey, for: apiHeaderKey, in: &fields)

        if let orgEnvKey, let org = environment.get(orgEnvKey) {
            try set(value: org, for: orgHeaderKey ?? orgEnvKey, in: &fields)
        }

        if let additionalHeaders {
            for (key, value) in additionalHeaders {
                try set(value: value, for: key, in: &fields)
            }
        }
    }

    /// Determine the upstream host for this provider, honouring any environment override.
    func resolvedHost(environment: Environment = Environment()) -> String {
        if let hostEnvKey, let override = environment.get(hostEnvKey), !override.isEmpty {
            return override
        }
        return host
    }

    /// Normalise the downstream path for this provider using its configured path prefix.
    func normalisedPath(withRemainder remainder: [Substring]) -> String {
        let baseSegments = pathPrefixSegments
        let remainderSegments = remainder.map { String($0) }

        let finalSegments: [String]
        if remainderSegments.isEmpty {
            finalSegments = baseSegments
        } else if baseSegments.isEmpty {
            finalSegments = remainderSegments
        } else if remainderSegments.starts(with: baseSegments) {
            finalSegments = remainderSegments
        } else {
            finalSegments = baseSegments + remainderSegments
        }

        guard !finalSegments.isEmpty else { return "/" }
        return "/" + finalSegments.joined(separator: "/")
    }

    /// Attach the provider slug and optional model to the headers if not already present.
    func annotate(headers: inout HTTPFields, model: String?) {
        headers[Self.providerHeaderField] = self.slug
        if let model, headers[Self.modelHeader] == nil {
            headers[Self.modelHeader] = model
        }
    }

    private func set(value: String, for name: String, in fields: inout HTTPFields) throws {
        guard let fieldName = HTTPField.Name(name) else {
            throw HTTPError(.internalServerError, message: "Invalid HTTP header name \(name)")
        }
        fields[fieldName] = value
    }

    private var pathPrefixSegments: [String] {
        guard let pathPrefix, !pathPrefix.isEmpty else { return [] }
        return pathPrefix.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static var providersDictionary: [String: LLMProvider] {
        Dictionary(uniqueKeysWithValues: providers.map { ($0.slug.lowercased(), $0) })
    }
}

