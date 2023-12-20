//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2021 the Hummingbird authors
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

/// Middleware forwarding requests onto another server
public struct HBProxyServerMiddleware: HBMiddleware {
    public struct Proxy {
        let location: String
        let target: String

        init(location: String, target: String) {
            self.location = location.dropSuffix("/")
            self.target = target.dropSuffix("/")
        }
    }

    let httpClient: HTTPClient
    let proxy: Proxy

    public init(httpClient: HTTPClient, proxy: Proxy) {
        self.httpClient = httpClient
        self.proxy = proxy
    }

    public func apply(to request: HBRequest, next: HBResponder) -> EventLoopFuture<HBResponse> {
        guard let responseFuture = forward(request: request, to: proxy) else {
            return next.respond(to: request)
        }
        return responseFuture
    }

    func forward(request: HBRequest, to proxy: Proxy) -> EventLoopFuture<HBResponse>? {
        guard request.uri.description.hasPrefix(proxy.location) else { return nil }
        let newURI = request.uri.description.dropFirst(proxy.location.count)
        guard newURI.first == nil || newURI.first == "/" else { return nil }

        do {
            // create request
            let ahcRequest = try request.ahcRequest(uri: String(newURI), host: proxy.target, eventLoop: request.eventLoop)

            request.logger.info("\(request.uri) -> \(ahcRequest.url)")

            // create response body streamer
            let streamer = HBByteBufferStreamer(eventLoop: request.eventLoop, maxSize: 2048 * 1024, maxStreamingBufferSize: 128 * 1024)
            // delegate for streaming bytebuffers from AsyncHTTPClient
            let delegate = StreamingResponseDelegate(on: request.eventLoop, streamer: streamer)
            // execute request
            _ = self.httpClient.execute(
                request: ahcRequest,
                delegate: delegate,
                eventLoop: .delegateAndChannel(on: request.eventLoop),
                logger: request.logger
            )
            // when delegate receives header then signal completion
            return delegate.responsePromise.futureResult
        } catch {
            return request.failure(.badRequest)
        }
    }
}

extension HBRequest {
    /// create AsyncHTTPClient request from Hummingbird Request
    func ahcRequest(uri: String, host: String, eventLoop: EventLoop) throws -> HTTPClient.Request {
        
        // Update headers with org and API key environment variables
        var headers = self.headers
        headers.remove(name: "host")
        guard let org = HBEnvironment().get("organization"), let apiKey = HBEnvironment().get("apiKey"), !org.isEmpty, !apiKey.isEmpty else {
            fatalError("apiKey and organization environment variables need to be set")
        }
        headers.replaceOrAdd(name: "OpenAI-Organization", value: org)
        headers.replaceOrAdd(name: "Authorization", value: "Bearer \(apiKey)")
        
        switch self.body {
        case .byteBuffer(let buffer):
            return try HTTPClient.Request(
                url: host + uri,
                method: self.method,
                headers: headers,
                body: buffer.map { .byteBuffer($0) }
            )

        case .stream(let stream):
            let contentLength = self.headers["content-length"].first.map { Int($0) } ?? nil
            return try HTTPClient.Request(
                url: host + uri,
                method: self.method,
                headers: headers,
                body: .stream(length: contentLength) { writer in
                    return stream.consumeAll(on: eventLoop) { byteBuffer in
                        writer.write(.byteBuffer(byteBuffer))
                    }
                }
            )
        }
    }
}

extension String {
    private func addSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return self
        } else {
            return self + suffix
        }
    }

    fileprivate func dropSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(self.dropLast(suffix.count))
        } else {
            return self
        }
    }
}
