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
        
        guard let org = HBEnvironment().get("organization"), let apiKey = HBEnvironment().get("apiKey"), !org.isEmpty, !apiKey.isEmpty else {
            
            return request.failure(.internalServerError, message: "apiKey and organization environment variables need to be set")
        }
        
        var request = request
        var headers = request.headers
        headers.replaceOrAdd(name: "OpenAI-Organization", value: org)
        headers.replaceOrAdd(name: "Authorization", value: "Bearer \(apiKey)")
        
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: request.uri.string, headers: headers)
        let updatedRequest = HBRequest(head: head, body: request.body, application: request.application, context: request.context)
        
        return next.respond(to: request)
    }
}

/*
 /// This is the async version of the OpenAIKey middleware. This version will only work if ProxyServerMiddleware is refactored to use async as well
struct OpenAIKeyMiddleware: HBAsyncMiddleware {
    func apply(to request: HBRequest, next: HBResponder) async throws -> HBResponse {
        
        guard let org = HBEnvironment().get("organization"), let apiKey = HBEnvironment().get("apiKey"), !org.isEmpty, !apiKey.isEmpty else {
            throw HBHTTPError(.internalServerError, message: "apiKey and organization environment variables need to be set")
        }
        
        var request = request
        var headers = request.headers
        headers.replaceOrAdd(name: "OpenAI-Organization", value: org)
        headers.replaceOrAdd(name: "Authorization", value: "Bearer \(apiKey)")
        
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: request.uri.string, headers: headers)
        let updatedRequest = HBRequest(head: head, body: request.body, application: request.application, context: request.context)
        
        var response = try await next.respond(to: updatedRequest)

//        response.headers.replaceOrAdd(name: "OpenAI-Organization", value: org)
//        response.headers.replaceOrAdd(name: "Authorization", value: "Bearer \(apiKey)")

        
//        response.headers.add(name: "My-App-Version", value: "v2.5.9")
        return response        
    }
}
*/
