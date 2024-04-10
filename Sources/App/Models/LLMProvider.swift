//
//  LLMProvider.swift
//  
//
//  Created by Ronald Mannak on 4/8/24.
//

import Foundation
import Hummingbird

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
    func setHeaders(headers: inout HTTPHeaders) throws {
        
        // 1. Set API key
        guard let apiKey = HBEnvironment().get(apiEnvKey) else {
            throw HBHTTPError(.internalServerError, message: "Environment API Key \(apiEnvKey) not set")
        }
        headers.replaceOrAdd(name: apiHeaderKey, value: (bearer ? "Bearer " + apiKey : apiKey))
        
        if let orgEnvKey, let org = HBEnvironment().get(orgEnvKey) {
            headers.replaceOrAdd(name: orgEnvKey, value: org)
        }
        
        if let additionalHeaders {
            for header in additionalHeaders {
                headers.replaceOrAdd(name: header.key, value: header.value)
            }
        }
    }
}

