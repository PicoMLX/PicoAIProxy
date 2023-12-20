import AsyncHTTPClient
import Hummingbird

public protocol AppArguments {
    var location: String { get }
    var target: String { get }
}

extension HBApplication {
    /// configure your application
    /// add middleware
    /// setup the encoder/decoder
    /// add your routes
    func configure(_ args: AppArguments) throws {
        self.httpClient = HTTPClient(eventLoopGroupProvider: .shared(self.eventLoopGroup))
        self.middleware.add(
            HBProxyServerMiddleware(
                httpClient: httpClient,
                proxy: .init(location: args.location, target: args.target)
            )
        )
    }
}

extension HBApplication {
    var httpClient: HTTPClient {
        get { self.extensions.get(\.httpClient) }
        set { self.extensions.set(\.httpClient, value: newValue) { httpClient in
            try httpClient.syncShutdown()
        }}
    }
}
