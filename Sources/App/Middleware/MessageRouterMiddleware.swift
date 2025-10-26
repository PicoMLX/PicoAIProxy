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
        let bodyString = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) ?? ""
        let data = bodyString.data(using: .utf8) ?? Data()

        var headers = request.headers
        let originalPath = request.head.path ?? request.uri.path
        let segments = Self.pathSegments(from: originalPath)

        var provider: LLMProvider?
        var path = originalPath

        if segments.count >= 2, let candidate = LLMProvider.provider(for: String(segments[0])) {
            provider = candidate
            let model = String(segments[1])
            let remainder = Array(segments.dropFirst(2))
            path = candidate.normalisedPath(withRemainder: remainder)
            candidate.annotate(headers: &headers, model: model)
        }

        if provider == nil, let model = LLMModel.fetchModel(from: data) {
            context.logger.info("Rerouting \(model.name) to \(model.provider.name)")
            if !model.proxy().location.isEmpty {
                path = model.proxy().location
            }
            model.provider.annotate(headers: &headers, model: model.name)
        }

        var head = request.head
        head.headerFields = headers
        head.path = path.isEmpty ? "/" : path

        let updatedRequest = Request(head: head, body: request.body)
        return try await next(updatedRequest, context)
    }

    private static func pathSegments(from path: String) -> [Substring] {
        path.split(separator: "/", omittingEmptySubsequences: true)
    }
}

