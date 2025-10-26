import AsyncHTTPClient
import FluentKit
import FluentSQLiteDriver
import Hummingbird
import HummingbirdAuth
import HummingbirdFluent
<<<<<<< Updated upstream:Sources/App/Application+build.swift
=======
import JWTKit
import Logging
>>>>>>> Stashed changes:Sources/App/Application+configure.swift
import NIOCore
import NIOPosix
import ServiceLifecycle

public protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
<<<<<<< Updated upstream:Sources/App/Application+build.swift
    var location: String { get }
    var target: String { get }
}

/// Request context for proxy
///
/// Stores remote address
struct ProxyRequestContext: RequestContext {
    var coreContext: CoreRequestContext
    let remoteAddress: SocketAddress?

    init(channel: Channel, logger: Logger) {
        self.coreContext = .init(allocator: channel.allocator, logger: logger)
        self.remoteAddress = channel.remoteAddress
    }
}

func buildApplication(_ args: some AppArguments) -> some ApplicationProtocol {
    let eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    
    
    
    
    let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
    let router = Router(context: ProxyRequestContext.self)
    router.middlewares.add(
        ProxyServerMiddleware(
            httpClient: httpClient,
            proxy: .init(location: args.location, target: args.target)
        )
    )
    var app = Application(
        router: router,
        configuration: .init(
            address: .hostname(args.hostname, port: args.port),
            serverName: "PicoAIProxy"
        ),
        eventLoopGroupProvider: .shared(eventLoopGroup)
    )
    app.addServices(HTTPClientService(client: httpClient))
    return app
}

struct HTTPClientService: Service {
    let client: HTTPClient

    func run() async throws {
        try? await gracefulShutdown()
        try await self.client.shutdown()
    }
}
/*
public protocol AppArguments {
=======
>>>>>>> Stashed changes:Sources/App/Application+configure.swift
    var location: String { get }
    var target: String { get }
}

<<<<<<< Updated upstream:Sources/App/Application+build.swift
extension HBApplication {
    /// configure your application
    /// add middleware
    /// setup the encoder/decoder
    /// add your routes
    func configure(_ args: AppArguments) async throws {
            
        // 1. Set up JSON encoder and decoder
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        (self.encoder as! JSONEncoder).dateEncodingStrategy = .iso8601
        self.httpClient = HTTPClient(eventLoopGroupProvider: .shared(self.eventLoopGroup))
        
        // 2. Add logging middleware
        self.logger.logLevel = .info
        self.middleware.add(HBLogRequestsMiddleware(.info))
        self.middleware.add(HBLogRequestsMiddleware(.debug))
        self.middleware.add(HBLogRequestsMiddleware(.error))
=======
struct ProxyRequestContext: AuthRequestContext {
    typealias Identity = User
    var coreContext: CoreRequestContextStorage
    var identity: User?
    let remoteAddress: SocketAddress?
>>>>>>> Stashed changes:Sources/App/Application+configure.swift

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.identity = nil
        self.remoteAddress = source.channel.remoteAddress
    }
}

func buildApplication(_ args: some AppArguments) async throws -> some ApplicationProtocol {
    let environment = Environment()
    let eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))

    let baseLogger = Logger(label: "PicoAIProxy")
    var logger = baseLogger
    if let logLevelRaw = environment.get("logLevel"), let logLevel = Logger.Level(rawValue: logLevelRaw) {
        logger.logLevel = logLevel
    }

    let fluentLogger = Logger(label: "PicoAIProxy.Fluent")
    let fluent = Fluent(eventLoopGroupProvider: .shared(eventLoopGroup), logger: fluentLogger)
    fluent.databases.use(.sqlite(.memory), as: .sqlite)
    await fluent.migrations.add(UserMigration())
    await fluent.migrations.add(UserRequestMigration())

    guard let jwtKey = environment.get("JWTPrivateKey"), !jwtKey.isEmpty else {
        logger.error("JWTPrivateKey environment variable must be set")
        throw HTTPError(.internalServerError)
    }

    let jwtLocalSignerKid = JWKIdentifier("_aiproxy_local_")
    let jwtAuthenticator = JWTAuthenticator(
        fluent: fluent,
        allowPassthrough: environment.get("allowKeyPassthrough") == "1"
    )
    jwtAuthenticator.useSigner(JWTSigner.hs256(key: jwtKey), kid: jwtLocalSignerKid)

    let router = Router(context: ProxyRequestContext.self)
    router.add(middleware: LogRequestsMiddleware(.info))
    router.add(middleware: LogRequestsMiddleware(.debug))
    router.add(middleware: LogRequestsMiddleware(.error))

    router.add(middleware: jwtAuthenticator)
    router.add(middleware: RateLimiterMiddleware(fluent: fluent))
    router.add(middleware: MessageRouterMiddleware())
    router.add(middleware: APIKeyMiddleware())
    let defaultProxy = ProxyServerMiddleware.Proxy(
        location: args.location,
        target: args.target.isEmpty ? "https://api.openai.com" : args.target
    )
    router.add(middleware: ProxyServerMiddleware(httpClient: httpClient, defaultProxy: defaultProxy))

    let appStoreAuthenticator = try? AppStoreAuthenticator(fluent: fluent)
    let appStoreController = AppStoreController(
        fluent: fluent,
        jwtSigners: jwtAuthenticator.jwtSigners,
        kid: jwtLocalSignerKid
    )
    appStoreController.addRoutes(to: router.group("appstore"), authenticator: appStoreAuthenticator)

    let effectivePort = Int(environment.get("PORT") ?? "\(args.port)") ?? args.port

    var app = Application(
        router: router,
        configuration: .init(
            address: .hostname(args.hostname, port: effectivePort),
            serverName: "PicoAIProxy"
        ),
        services: [fluent],
        eventLoopGroupProvider: .shared(eventLoopGroup),
        logger: logger
    )

    app.addServices(HTTPClientService(client: httpClient))
    app.beforeServerStarts {
        try await fluent.migrate()
    }

    return app
}

struct HTTPClientService: Service {
    let client: HTTPClient

    func run() async throws {
        try? await gracefulShutdown()
        try await client.shutdown()
    }
}
*/
