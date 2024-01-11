import AsyncHTTPClient
import Hummingbird
import Foundation
import JWTKit
import HummingbirdAuth

public protocol AppArguments {
    var location: String { get }
    var target: String { get }
}

extension HBApplication {
    /// configure your application
    /// add middleware
    /// setup the encoder/decoder
    /// add your routes
    func configure(_ args: AppArguments) async throws {
        
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        (self.encoder as! JSONEncoder).dateEncodingStrategy = .iso8601
        
//        self.httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        self.httpClient = HTTPClient(eventLoopGroupProvider: .shared(self.eventLoopGroup))
        
        // Add logging middleware
        self.logger.logLevel = .info
        self.middleware.add(HBLogRequestsMiddleware(.info))
        
        //
        self.middleware.add(HBLogRequestsMiddleware(.debug))
        self.middleware.add(
            HBCORSMiddleware(
                allowOrigin: .originBased,
                allowHeaders: ["Accept", "Authorization", "Content-Type", "Origin"],
                allowMethods: [.GET, .OPTIONS]
            ))
        
        // add Fluent
//        self.addFluent()
//        // add sqlite database
//        if arguments.inMemoryDatabase {
//            self.fluent.databases.use(.sqlite(.memory), as: .sqlite)
//        } else {
//            self.fluent.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
//        }
//        // add migrations
//        self.fluent.migrations.add(CreateUser())
//        // migrate
//        if arguments.migrate || arguments.inMemoryDatabase {
//            try await self.fluent.migrate()
//        }
        
        
        // Add App attestation middleware
//        let attestationController = AttestationController()
//        attestationController.addRoutes(to: self.router.group("attestation"))
//        self.middleware.add(AttestationMiddleware(attestationController: attestationController))        
        
        // Add App Store middleware
//        let appStoreController = AppStoreController()
//        appStoreController.addRoutes(to: self.router.group("appstore"))
        
        // fetch JWT private key from environment
        guard let jwtKey = HBEnvironment().get("JWTPrivateKey"),
              !jwtKey.isEmpty else {
            self.logger.error("JWTPrivateKey environment variable must be set")
            throw HBHTTPError(.internalServerError) 
        }
        
        // Set up JWT authenticator
        let jwtAuthenticator = JWTAuthenticator()
        let jwtLocalSignerKid = JWKIdentifier("_aiproxy_local_")
        jwtAuthenticator.useSigner(.hs256(key: jwtKey), kid: jwtLocalSignerKid)

        // Add AppStoreController routes
        let appStoreController = AppStoreController(jwtSigners: jwtAuthenticator.jwtSigners, kid: jwtLocalSignerKid)
        appStoreController.addRoutes(to: self.router.group("appstore"))
        
        // Add AppStore
//        self.middleware.add(AppStoreMiddleware())
        self.middleware.add(jwtAuthenticator)
        
//        router.get("/") { _ in
//            return "Hello"
//        }
//        UserController(jwtSigners: jwtAuthenticator.jwtSigners, kid: jwtLocalSignerKid).addRoutes(to: router.group("user"))
//
//        router.group("auth")
//            .add(middleware: jwtAuthenticator)
//            .get("/") { request in
//                let user = try request.authRequire(User.self)
//                return "Authenticated (Subject: \(user.name))"
//            }
        
        // OpenAI API key middleware
        self.middleware.add(OpenAIKeyMiddleware())
        
        // Add Proxy middleware
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
