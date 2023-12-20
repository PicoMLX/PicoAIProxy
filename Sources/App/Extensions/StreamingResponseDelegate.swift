//
//  File.swift
//  
//
//  Created by Ronald Mannak on 12/19/23.
//

import AsyncHTTPClient
import Hummingbird
import HummingbirdCore
import NIOCore
import NIOHTTP1

final class StreamingResponseDelegate: HTTPClientResponseDelegate {
    typealias Response = HBResponse

    enum State {
        case idle
        case head(HTTPResponseHead)
        case error(Error)
    }

    let streamer: HBByteBufferStreamer
    let responsePromise: EventLoopPromise<Response>
    let eventLoop: EventLoop
    var state: State

    init(on eventLoop: EventLoop, streamer: HBByteBufferStreamer) {
        self.eventLoop = eventLoop
        self.streamer = streamer
        self.responsePromise = eventLoop.makePromise()
        self.state = .idle
    }

    func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        switch self.state {
        case .idle:
            let response = Response(status: head.status, headers: head.headers, body: .stream(self.streamer))
            self.responsePromise.succeed(response)
            self.state = .head(head)
        case .error:
            break
        default:
            preconditionFailure("Unexpected state \(self.state)")
        }
        return self.eventLoop.makeSucceededVoidFuture()
    }

    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        switch self.state {
        case .head:
            return self.streamer.feed(buffer: buffer)
        case .error:
            break
        default:
            preconditionFailure("Unexpected state \(self.state)")
        }
        return self.eventLoop.makeSucceededVoidFuture()
    }

    func didFinishRequest(task: HTTPClient.Task<Response>) throws -> HBResponse {
        switch self.state {
        case .head(let head):
            self.state = .idle
            self.streamer.feed(.end)
            return .init(status: head.status, headers: head.headers, body: .stream(self.streamer))
        case .error(let error):
            print(error.localizedDescription)
            throw error
        default:
            preconditionFailure("Unexpected state \(self.state)")
        }
    }

    func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
        self.streamer.feed(.error(error))
        self.responsePromise.fail(error)
        self.state = .error(error)
    }
}
