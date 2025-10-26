//
//  MessageParserMiddleware.swift
//
//
//  Created by Ronald Mannak on 4/6/24.
//

import Foundation
import Hummingbird
import HTTPTypes

/// Note: The Anthropic API is very picky. `max_tokens` is required (an option in OpenAI) and the
/// roles must alternate between `user` and `assistant`. It won't accept multiple `user` roles in a row
/// and extra inputs are not permitted (e.g. `user`)
struct MessageRouterMiddleware: RouterMiddleware {
    typealias Context = ProxyRequestContext

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if request.uri.path.hasPrefix("/appstore") {
            return try await next(request, context)
        }

        var request = request
        let buffer = try await request.collectBody(upTo: context.maxUploadSize)
        guard let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes),
              let data = body.data(using: .utf8) else {
            context.logger.error("Unable to decode body in MessageRouterMiddleware")
            throw HTTPError(.badRequest)
        }

        var headers = request.headers
        var path = request.head.path ?? request.uri.path

        if let model = LLMModel.fetchModel(from: data) {
            context.logger.info("Rerouting \(model.name) to \(model.provider.name)")
            if let modelHeader = HTTPField.Name("model") {
                headers[modelHeader] = model.name
            }
            if !model.proxy().location.isEmpty {
                path = model.proxy().location
            }
        }

        var head = request.head
        head.headerFields = headers
        head.path = path

        let updatedRequest = Request(head: head, body: request.body)
        return try await next(updatedRequest, context)
    }
}

