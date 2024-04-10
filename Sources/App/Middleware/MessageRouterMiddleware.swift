//
//  MessageParserMiddleware.swift
//
//
//  Created by Ronald Mannak on 4/6/24.
//

import Foundation
import Hummingbird
import NIOHTTP1

/// Note: The Anthropic API is very picky. `max_tokens` is required (an option in OpenAI) and the
/// roles must alternate between `user` and `assistant`. It won't accept multiple `user` roles in a row
/// and extra inputs are not permitted (e.g. `user`)
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
        var uri = request.uri.string
        if let model = LLMModel.fetchModel(from: data) {
            request.logger.info("Rerouting \(model.name) to \(model.provider.name)")
            headers.replaceOrAdd(name: "model", value: model.name)
            if !model.proxy().location.isEmpty {
                uri = model.proxy().location
            }
        }
        
        // 3. Update header
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: uri, headers: headers)
        let convertedRequest = HBRequest(head: head, body: request.body, application: request.application, context: request.context)
        
        return try await next.respond(to: convertedRequest)
    }
}

