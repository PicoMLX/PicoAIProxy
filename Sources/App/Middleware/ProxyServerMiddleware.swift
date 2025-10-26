//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2024 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Hummingbird
import HummingbirdCore
import Logging
import HTTPTypes
import NIOHTTPTypesHTTP1

/// Middleware forwarding requests onto another server based on the selected provider or model.
struct ProxyServerMiddleware: RouterMiddleware {
    typealias Context = ProxyRequestContext

    struct Proxy: Sendable {
        let location: String
        let target: String

        init(location: String, target: String) {
            self.location = location.dropSuffix("/")
            self.target = target.dropSuffix("/")
        }
    }

    private static let modelHeader = HTTPField.Name("model")!

    let httpClient: HTTPClient
    let defaultProxy: Proxy

    init(httpClient: HTTPClient, defaultProxy: Proxy = Proxy(location: "", target: "https://api.openai.com")) {
        self.httpClient = httpClient
        self.defaultProxy = defaultProxy
    }

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if request.uri.path.hasPrefix("/search") {
            return try await next(request, context)
        }
        let selectedProxy = proxy(for: request)

        guard let response = try await forward(request: request, to: selectedProxy, context: context) else {
            return try await next(request, context)
        }
        return response
    }

    private func proxy(for request: Request) -> Proxy {
        let environment = Environment()

        if let providerSlug = request.headers[LLMProvider.providerHeaderField],
           let provider = LLMProvider.provider(for: providerSlug) {
            let location = provider.pathPrefix ?? ""
            let target = provider.resolvedHost(environment: environment)
            return Proxy(location: location, target: target)
        }

        if let modelName = request.headers[Self.modelHeader],
           let model = LLMModel.fetch(model: modelName) {
            return model.proxy()
        }

        return defaultProxy
    }

    private func forward(request: Request, to proxy: Proxy, context: Context) async throws -> Response? {
        let currentPath = request.uri.description
        guard currentPath.hasPrefix(proxy.location) else { return nil }
        guard currentPath.first == "/" else { return nil }

        var clientRequest = HTTPClientRequest(url: "\(proxy.target)\(currentPath)")
        clientRequest.method = .init(request.method)
        clientRequest.headers = .init(request.headers)

        // Remove internal routing headers before forwarding upstream
        clientRequest.headers.remove(name: LLMProvider.providerHeaderName)

        if let modelName = request.headers[Self.modelHeader] {
            clientRequest.headers.replaceOrAdd(name: "model", value: modelName)
        }

        if let remoteAddress = context.remoteAddress {
            switch remoteAddress {
            case .v4:
                if let ip = remoteAddress.ipAddress {
                    clientRequest.headers.add(name: "Forwarded", value: "for=\(ip)")
                }
            case .v6:
                if let ip = remoteAddress.ipAddress {
                    clientRequest.headers.add(name: "Forwarded", value: "for=\"[\(ip)]\"")
                }
            default:
                break
            }
        }

        if clientRequest.headers.contains(name: "host") {
            clientRequest.headers.remove(name: "host")
        }

        let contentLength = request.headers[.contentLength].flatMap { Int($0) }
        clientRequest.body = .stream(
            request.body,
            length: contentLength.map { HTTPClientRequest.Body.Length.known($0) } ?? .unknown
        )

        do {
            let response = try await httpClient.execute(clientRequest, timeout: .seconds(60))
            context.logger.info("\(request.uri) -> \(clientRequest.url)")
            return Response(
                status: .init(code: Int(response.status.code), reasonPhrase: response.status.reasonPhrase),
                headers: .init(response.headers, splitCookie: false),
                body: .init(asyncSequence: response.body)
            )
        } catch {
            context.logger.error("Client error: \(error)")
            throw error
        }
    }
}

extension String {
    fileprivate func dropSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(self.dropLast(suffix.count))
        } else {
            return self
        }
    }
}
