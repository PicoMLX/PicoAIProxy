//
//  File.swift
//  
//
//  Created by Ronald Mannak on 4/8/24.
//

import Foundation

extension LLMProvider {
    
    static var providers = [openAI, anthropic]
    
    static var openAI = LLMProvider(
        name: "OpenAI",
        host: "https://api.openai.com",
        apiEnvKey: "OpenAI-APIKey",
        apiHeaderKey: "Authorization",
        bearer: true,
        orgEnvKey: "OpenAI-Organization",
        orgHeaderKey: "OpenAI-Organization",
        additionalHeaders: nil
    )
    
    static var anthropic = LLMProvider(
        name: "Anthropic",
        host: "https://api.anthropic.com",
        apiEnvKey: "Anthropic-APIKey",
        apiHeaderKey: "x-api-key",
        bearer: false,
        orgEnvKey: nil,
        orgHeaderKey: nil,
        additionalHeaders: ["anthropic-version": "2023-06-01"]
    )
    
    static var groq = LLMProvider(
        name: "Groq",
        host: "https://api.groq.com",
        apiEnvKey: "Groq-APIKey",
        apiHeaderKey: "Authorization",
        bearer: true,
        orgEnvKey: nil,
        orgHeaderKey: nil,
        additionalHeaders: nil)
}

extension LLMModel {
    static var models = [LLMModel]()
    
    private static let gptModels = ["gpt-4-turbo", "gpt-4-turbo-2024-04-09", "gpt-4-0125-preview", "gpt-4-turbo-preview", "gpt-4-1106-preview", "gpt-4-vision-preview", "gpt-4-1106-vision-preview", "gpt-4", "gpt-4-0613", "gpt-4-32k", "gpt-4-32k-0613", "gpt-3.5-turbo-0125", "gpt-3.5-turbo", "gpt-3.5-turbo-1106", "gpt-3.5-turbo-16k", "gpt-3.5-turbo-0613", "gpt-3.5-turbo-16k-0613"]
    private static let claudeModels = ["claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"]
    private static let groqModels = ["llama3-8b-8192", "llama3-70b-8192", "mixtral-8x7b-32768", "gemma-7b-it"]
    
    static func load() {
        for model in gptModels {
            models.append(LLMModel(name: model, endpoint: "", provider: LLMProvider.openAI)) // leaving endpoint empty so all calls will be forwarded to original path /v1/chat/completions
        }
        for model in claudeModels {
            models.append(LLMModel(name: model, endpoint: "/v1/messages", provider: LLMProvider.anthropic))
        }
        for model in groqModels {
            models.append(LLMModel(name: model, endpoint: "/openai/v1/chat/completions", provider: LLMProvider.groq))
        }
    }
}
