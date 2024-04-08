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

        // 2. Decode body
        let decoder = JSONDecoder()
        if let chat = try? decoder.decode(Chat.self, from: data) {
            request.logger.info("Decoded chat: \(chat.model)")
        } else {
            // just forward message
            request.logger.info("MessageRouterMiddleware: Could not decode chat")
        }
    
        return try await next.respond(to: request)
    }
}

