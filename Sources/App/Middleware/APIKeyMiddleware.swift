//
//  APIKeyMiddleware.swift
//  
//
//  Created by Ronald Mannak on 12/29/23.
//

import Hummingbird
import NIOHTTP1

struct APIKeyMiddleware: HBMiddleware {
    func apply(to request: Hummingbird.HBRequest, next: Hummingbird.HBResponder) -> NIOCore.EventLoopFuture<Hummingbird.HBResponse> {
        
        var headers = request.headers
        
        do {
            if let modelName = headers.first(name: "model"), let model = LLMModel.fetch(model: modelName) {
                try model.provider.setHeaders(headers: &headers)
            } else {
                // Default to OpenAI
                try LLMProvider.openAI.setHeaders(headers: &headers)
            }
        } catch {
            request.logger.error("Error OpenAIKeyMiddleware: \(error.localizedDescription)")
            return request.failure(error)
        }
        
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: request.uri.string, headers: headers)
        let request = HBRequest(head: head, body: request.body, application: request.application, context: request.context)
        
        return next.respond(to: request)
    }
}
