//
//  HBProxyServerMiddleware.swift
//
//
//  Created by Ronald Mannak on 12/29/23.
//

import AsyncHTTPClient
import Hummingbird
import HummingbirdCore
import Logging


// Note: I wanted to refactor the proxy server to use async await since it's
// easier to read and because it seems all middleware in HummingBird have
// to be all either closure-based or async. But it doesn't work yet
// https://github.com/swift-server/async-http-client/blob/main/Examples/StreamingByteCounter/StreamingByteCounter.swift
/*

/// Middleware forwarding requests onto another server
public struct HBProxyServerMiddleware: HBAsyncMiddleware {
    
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

    public func apply(to request: HBRequest, next: HBResponder) async throws -> HBResponse {
        do {
            let response = try await forward(request: request, to: proxy)
            return response
        } catch {
            return try await next.respond(to: request)
        }
    }

    
    func forward(request: HBRequest, to proxy: Proxy) async throws-> HBResponse {

        guard request.uri.description.hasPrefix(proxy.location) else { throw HBHTTPError(.internalServerError) }
        let newURI = request.uri.description.dropFirst(proxy.location.count)
        guard newURI.first == nil || newURI.first == "/" else { throw HBHTTPError(.internalServerError) }

            // create request
        let ahcRequest = try request.ahcRequest(uri: String(newURI), host: proxy.target, eventLoop: request.eventLoop)
        
        request.logger.info("\(request.uri) -> \(ahcRequest.url)")
        
        let response = try await httpClient.execute(ahcRequest, timeout: .seconds(30))
        print("HTTP head", response)
        
        // if defined, the content-length headers announces the size of the body
        let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init)
        
        var receivedBytes = 0
        // asynchronously iterates over all body fragments
        // this loop will automatically propagate backpressure correctly
        for try await buffer in response.body {
            // For this example, we are just interested in the size of the fragment
            receivedBytes += buffer.readableBytes
            
            if let expectedBytes = expectedBytes {
                // if the body size is known, we calculate a progress indicator
                let progress = Double(receivedBytes) / Double(expectedBytes)
                print("progress: \(Int(progress * 100))%")
            }
        }
        print("did receive \(receivedBytes) bytes")
        
        
        
        // create response body streamer
//        let streamer = HBByteBufferStreamer(eventLoop: request.eventLoop, maxSize: 2048 * 1024, maxStreamingBufferSize: 128 * 1024)
        // delegate for streaming bytebuffers from AsyncHTTPClient
//        let delegate = StreamingResponseDelegate(on: request.eventLoop, streamer: streamer)
        // execute request
//        _ = self.httpClient.execute(
//            request: ahcRequest,
//            delegate: delegate,
//            eventLoop: .delegateAndChannel(on: request.eventLoop),
//            logger: request.logger
//        )
        // when delegate receives header then signal completion
//        return delegate.responsePromise.futureResult
    }
}

extension HBRequest {
    
    // Create HTTPClientRequest from Hummingbird Request
    func ahcRequest(uri: String, host: String) throws -> HTTPClientRequest {
        
        var headers = self.headers
        headers.remove(name: "host")
        
        var request = HTTPClientRequest(url: host + uri)
        request.headers = self.headers
        request.method = self.method
        
        switch self.body {
        case .byteBuffer(let buffer):

            request.body = buffer.map { .byteBuffer($0) }
            return request

        case .stream(let stream):
            let contentLength = self.headers["content-length"].first.map { Int($0) } ?? nil
            
            request.body = .stream(length: contentLength) { writer in
                return stream.consumeAll(on: eventLoop) { byteBuffer in
                    writer.write(.byteBuffer(byteBuffer))
                }
            }
        }
        return request
    }
    
//    self.url = url
//    self.method = .GET
//    self.headers = .init()
//    self.body = .none
//    self.tlsConfiguration = nil
    
    /// create AsyncHTTPClient request from Hummingbird Request
    func ahcRequest(uri: String, host: String, eventLoop: EventLoop) throws -> HTTPClient.Request {
        
        var headers = self.headers
        headers.remove(name: "host")
//        guard let org = HBEnvironment().get("organization"), let apiKey = HBEnvironment().get("apiKey"), !org.isEmpty, !apiKey.isEmpty else {
//            fatalError("apiKey and organization environment variables need to be set")
//        }
//        headers.replaceOrAdd(name: "OpenAI-Organization", value: org)
//        headers.replaceOrAdd(name: "Authorization", value: "Bearer \(apiKey)")
        
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

*/
