//
//  OpenAIKeyMiddleware.swift
//  
//
//  Created by Ronald Mannak on 12/29/23.
//

import Hummingbird
import NIOHTTP1

struct OpenAIKeyMiddleware: HBMiddleware {
    func apply(to request: Hummingbird.HBRequest, next: Hummingbird.HBResponder) -> NIOCore.EventLoopFuture<Hummingbird.HBResponse> {
        
        guard let org = HBEnvironment().get("OpenAI-Organization"), let apiKey = HBEnvironment().get("OpenAI-APIKey"), !org.isEmpty, !apiKey.isEmpty else {
            return request.failure(.internalServerError, message: "apiKey and organization environment variables need to be set")
        }
        
        var headers = request.headers
        headers.replaceOrAdd(name: "OpenAI-Organization", value: org)
        headers.replaceOrAdd(name: "Authorization", value: "Bearer \(apiKey)")
        
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: request.uri.string, headers: headers)
        let request = HBRequest(head: head, body: request.body, application: request.application, context: request.context)
        
        return next.respond(to: request)
    }
}
