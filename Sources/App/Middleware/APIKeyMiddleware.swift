//
//  APIKeyMiddleware.swift
//  
//
//  Created by Ronald Mannak on 12/29/23.
//

import Hummingbird
import HTTPTypes

struct APIKeyMiddleware: RouterMiddleware {
    typealias Context = ProxyRequestContext

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if request.uri.path.hasPrefix("/appstore") {
            return try await next(request, context)
        }

        var headers = request.headers
        headers[.authorization] = nil

        do {
            if let modelHeader = HTTPField.Name("model"),
               let modelName = headers[modelHeader],
               let model = LLMModel.fetch(model: modelName) {
                try model.provider.setHeaders(fields: &headers)
            } else {
                try LLMProvider.openAI.setHeaders(fields: &headers)
            }
        } catch {
            context.logger.error("Error APIKeyMiddleware: \(error.localizedDescription)")
            throw HTTPError(.internalServerError, message: "Unable to prepare upstream request headers")
        }

        var head = request.head
        head.headerFields = headers
        let updatedRequest = Request(head: head, body: request.body)
        return try await next(updatedRequest, context)
    }
}
