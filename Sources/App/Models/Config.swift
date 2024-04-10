//
//  Config.swift
//
//
//  Created by Ronald Mannak on 1/25/24.
//

import Foundation
/*
 struct Config: Codable {
 
 let proxies: [ProxyConfig]
 
 let spendingLimits: [SpendingLimit]?
 }
 
 struct ProxyConfig: Codable {
 
 /// E.g. ["gpt-4-0125-preview", "gpt-3.5-turbo", "text-embedding-3-small"]
 let models: [LLMModel]
 
 /// The label of the environment variable containing the API key value.
 /// Warning: do not store the API key itself here. The API key should be stored in
 /// an environment variable named the keyLabel value
 /// E.g. OpenAILabel
 let keyLabel: String
 
 /// The label of the environment variable containing the organization key value.
 /// orgLabel should be nil for APIs that don't require a organization
 /// Warning: do not store the organization key itself here. The organization key should be stored in
 /// an environment variable named the orgLabel value
 /// E.g. OpenAIKey
 let orgLabel: String?
 
 /// E.g. https://api.openai.com/v1/chat/completions
 let endpoint: URL
 
 }
 
 struct LLMModel: Codable {
 
 /// E.g. "gpt-4-0125-preview"
 let model: String
 
 /// Price in USD per 1K tokens. For example, for gpt-3.5-turbo the value is 0.0015
 let price: Float
 }
 
 /// Type of APIs supported
 enum LLMAPI: Int, Codable {
 case openAI
 }
 
 struct SpendingLimit: Codable {
 
 // E.g. "pico.subscription.lite"
 let productIdLabel: String
 
 // E.g. 4
 let monthlyLimitLabel: String
 }
 */
