//
//  LLMModel.swift
//  
//
//  Created by Ronald Mannak on 4/9/24.
//

import Foundation

struct LLMModel: Codable {
    
    /// E.g. `gpt-3.5` or `gpt-4`
    let name: String
    
    /// E.g. `https://api.openai.com/v1/chat/completions` or `https://api.openai.com/v1/embeddings`
    let endpoint: String
    
    let provider: LLMProvider
}

extension LLMModel {
    
    func proxy() -> HBProxyServerMiddleware.Proxy {
        HBProxyServerMiddleware.Proxy(location: endpoint, target: provider.host)
    }
    
    static func fetch(model: String) -> LLMModel? {
        return models.filter({ $0.name == model }).first
    }
    
    static func fetchModel(from chat: Data) -> LLMModel? {
        let decoder = JSONDecoder()
        if let chat = try? decoder.decode(Chat.self, from: chat) {
            return fetch(model: chat.model)
        } else {
            return nil
        }
    }
}
