import AsyncHTTPClient
import FluentKit
import FluentSQLiteDriver
import Hummingbird
import HummingbirdAuth
import HummingbirdFluent
import JWTKit
import Logging
import NIOCore
import NIOPosix
import ServiceLifecycle

public protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
    var location: String { get }
    var target: String { get }
}

struct ProxyRequestContext: AuthRequestContext {
    typealias Identity = User

    var coreContext: CoreRequestContextStorage
    var identity: User?
    let remoteAddress: SocketAddress?
    let maxUploadSize: Int

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.identity = nil
        self.remoteAddress = source.channel.remoteAddress
        self.maxUploadSize = 5 * 1024 * 1024
    }
}

func buildApplication(_ args: some AppArguments) async throws -> some ApplicationProtocol {
    let environment = Environment()
    let eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))

    var logger = Logger(label: "PicoAIProxy")
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

    let defaultTarget = args.target.isEmpty ? "https://api.openai.com" : args.target
    let defaultProxy = ProxyServerMiddleware.Proxy(location: args.location, target: defaultTarget)
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
