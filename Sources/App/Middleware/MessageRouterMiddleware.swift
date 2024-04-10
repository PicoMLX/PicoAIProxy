//
//  MessageParserMiddleware.swift
//
//
//  Created by Ronald Mannak on 4/6/24.
//

import Foundation
import Hummingbird
import NIOHTTP1

// ChatRouterMiddleware
struct MessageRouterMiddleware: HBAsyncMiddleware {
    
    func apply(to request: Hummingbird.HBRequest, next: any Hummingbird.HBResponder) async throws -> Hummingbird.HBResponse {
        
        // 1. Fetch body
        let request = try await request.collateBody().get()
        guard let buffer = request.body.buffer, let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes), let data = body.data(using: .utf8) else {
            request.logger.error("Unable to decode body in MessageRouterMiddleware")
            throw HBHTTPError(.badRequest)
        }

        // 2. Find model in body. Default to OpenAI if body isn't a chat (but e.g. an embedding)
        var headers = request.headers
        if let model = LLMModel.fetchModel(from: data) {
            request.logger.info("Rerouting \(model.name) to \(model.provider.name)")
            headers.replaceOrAdd(name: "model", value: model.name)
        }
        
        // 3. Update header
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: request.uri.string, headers: headers)
        let convertedRequest = HBRequest(head: head, body: request.body, application: request.application, context: request.context)
        
        return try await next.respond(to: convertedRequest)
    }
}

