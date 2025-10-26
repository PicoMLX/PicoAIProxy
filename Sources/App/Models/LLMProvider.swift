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
    
    /// The name of the provider, e.g. `OpenAI`
    let name: String
    
    /// E.g. `api.openai.com`
    let host: String
    
    /// The name of the environment key that stores the API key
    /// E.g. `OpenAI-APIKey`
    let apiEnvKey: String
    
    /// The HTTP header key for the API key
    /// E.g. `Authorization`
    let apiHeaderKey: String
    
    /// Adds `Bearer` to API key header value if true
    let bearer: Bool
    
    /// The name of the environment key that stores the API key
    /// E.g. `OpenAI-Organization`
    let orgEnvKey: String?
    
    /// The HTTP header key for the organization key
    /// E.g. `OpenAI-Organization`
    let orgHeaderKey: String?
    
    let additionalHeaders: [String: String]?
}

extension LLMProvider {
    
    
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

    private func set(value: String, for name: String, in fields: inout HTTPFields) throws {
        guard let fieldName = HTTPField.Name(name) else {
            throw HTTPError(.internalServerError, message: "Invalid HTTP header name \(name)")
        }
        fields[fieldName] = value
    }
}

