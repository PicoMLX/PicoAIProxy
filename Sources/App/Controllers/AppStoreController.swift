import FluentKit
import Hummingbird
import HummingbirdAuth
import HummingbirdFluent
import JWTKit

struct AppStoreController {
    let fluent: Fluent
    let jwtSigners: JWTSigners
    let kid: JWKIdentifier

    func addRoutes(to group: RouterGroup<ProxyRequestContext>, authenticator: AppStoreAuthenticator?) {
        guard let authenticator else {
            group.post("/", use: incorrectSetup)
            return
        }

        group
            .add(middleware: authenticator)
            .post("/", use: login)
    }

    @Sendable
    private func incorrectSetup(_ request: Request, context: ProxyRequestContext) async throws -> String {
        context.logger.error("Missing environment variable(s): IAPPrivateKey, IAPIssuerId, IAPKeyId, appBundleId and/or appAppleId")
        throw HTTPError(.internalServerError, message: "IAPPrivateKey, IAPIssuerId, IAPKeyId and/or appBundleId environment variables not set")
    }

    @Sendable
    private func login(_ request: Request, context: ProxyRequestContext) async throws -> [String: String] {
        let user = try context.requireIdentity()
        context.logger.info("Starting login for user \(user.appAccountToken?.uuidString ?? "anon")")

        let db = fluent.db()
        if try await User.query(on: db)
            .filter(\.$appAccountToken == user.appAccountToken)
            .first() == nil {
            try await user.save(on: db)
            context.logger.info("Saved user with app account token \(user.appAccountToken?.uuidString ?? "anon")")
        }

        let payload = JWTPayloadData(
            subject: .init(value: user.appAccountToken?.uuidString ?? "NO_ACCOUNT"),
            expiration: .init(value: Date(timeIntervalSinceNow: 12 * 60 * 60))
        )

        let token = try jwtSigners.sign(payload, kid: kid)

        user.jwtToken = token
        try await user.save(on: db)

        return ["token": token]
    }
}
