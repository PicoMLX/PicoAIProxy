import FluentKit
import Foundation
import Hummingbird
import HummingbirdFluent
import HTTPTypes
import AppStoreServerLibrary
import Logging
#if os(Linux)
import FoundationNetworking
#endif

typealias StoreEnvironment = AppStoreServerLibrary.Environment

struct AppStoreAuthenticator: RouterMiddleware {
    typealias Context = ProxyRequestContext

    let fluent: Fluent
    let iapKey: String
    let iapIssuerId: String
    let iapKeyId: String
    let bundleId: String
    let appAppleId: Int64

    init(fluent: Fluent) throws {
        self.fluent = fluent
        let environment = Environment()
        guard let iapKeyRaw = environment.get("IAPPrivateKey")?.replacingOccurrences(of: "\\\n", with: "\n"),
              !iapKeyRaw.isEmpty,
              let issuerId = environment.get("IAPIssuerId"), !issuerId.isEmpty,
              let keyId = environment.get("IAPKeyId"), !keyId.isEmpty,
              let bundleId = environment.get("appBundleId"), !bundleId.isEmpty,
              let appAppleIdString = environment.get("appAppleId"),
              let appAppleId = Int64(appAppleIdString)
        else {
            throw HTTPError(.internalServerError, message: "IAPPrivateKey, IAPIssuerId, IAPKeyId and/or appBundleId, appAppleId environment variable(s) not set")
        }

        self.iapKey = iapKeyRaw
        self.iapIssuerId = issuerId
        self.iapKeyId = keyId
        self.bundleId = bundleId
        self.appAppleId = appAppleId
    }

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        guard request.uri.path.hasPrefix("/appstore") else {
            return try await next(request, context)
        }

        var request = request
        let body = try await collectBodyString(&request, maxSize: context.maxUploadSize)
        let logger = context.logger
        let db = fluent.db()

        if let payload = try await validateJWS(jws: body, environment: .production, logger: logger) {
            let user = try await addUser(payload: payload, environment: .production, db: db, logger: logger)
            var context = context
            context.identity = user
            return try await next(request, context)
        }

        if let payload = try await validateJWS(jws: body, environment: .sandbox, logger: logger) {
            let user = try await addUser(payload: payload, environment: .sandbox, db: db, logger: logger)
            var context = context
            context.identity = user
            return try await next(request, context)
        }

        if let payload = try await validateJWS(jws: body, environment: .xcode, logger: logger) {
            let user = try await addUser(payload: payload, environment: .xcode, db: db, logger: logger)
            var context = context
            context.identity = user
            return try await next(request, context)
        }

        guard let transactionId = ReceiptUtility.extractTransactionId(appReceipt: body) else {
            throw HTTPError(.unauthorized)
        }

        do {
            if let user = try await validate(transactionId: transactionId, environment: .production, db: db, logger: logger) {
                var context = context
                context.identity = user
                return try await next(request, context)
            }
        } catch let error as HTTPError where error.status == .notFound {
            logger.error("AppStoreAuthenticator: production lookup failed. Trying sandbox for transaction \(transactionId)")
            if let user = try await validate(transactionId: transactionId, environment: .sandbox, db: db, logger: logger) {
                var context = context
                context.identity = user
                return try await next(request, context)
            }
        }

        throw HTTPError(.unauthorized)
    }

    private func collectBodyString(_ request: inout Request, maxSize: Int) async throws -> String {
        let buffer = try await request.collectBody(upTo: maxSize)
        guard let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
            throw HTTPError(.badRequest)
        }
        return body
    }

    private func validateJWS(jws: String, environment: StoreEnvironment, logger: Logger) async throws -> JWSTransactionDecodedPayload? {
        let rootCertificates = try loadAppleRootCertificates(logger: logger)
        let verifier = try SignedDataVerifier(
            rootCertificates: rootCertificates,
            bundleId: bundleId,
            appAppleId: appAppleId,
            environment: environment,
            enableOnlineChecks: true
        )

        let response = await verifier.verifyAndDecodeTransaction(signedTransaction: jws)
        switch response {
        case .valid(let payload):
            if let expires = payload.expiresDate, expires < Date() {
                logger.error("Subscription for \(payload.appAccountToken?.uuidString ?? "anon") expired on \(expires)")
                throw HTTPError(.unauthorized)
            }
            if let revoked = payload.revocationDate, revoked < Date() {
                logger.error("Subscription for \(payload.appAccountToken?.uuidString ?? "anon") revoked on \(revoked)")
                throw HTTPError(.unauthorized)
            }
            logger.info("Validated JWS for user \(payload.appAccountToken?.uuidString ?? "anon") in \(environment.rawValue)")
            return payload

        case .invalid(let error):
            switch error {
            case .INVALID_ENVIRONMENT:
                return nil
            case .INVALID_JWT_FORMAT, .INVALID_CERTIFICATE, .VERIFICATION_FAILURE, .INVALID_APP_IDENTIFIER:
                logger.error("AppStoreAuthenticator: JWS validation failed with \(error)")
                return nil
            }
        }
    }

    private func addUser(payload: JWSTransactionDecodedPayload, environment: StoreEnvironment, db: Database, logger: Logger) async throws -> User {
        let token = payload.appAccountToken
        if let existing = try await User.query(on: db)
            .filter(\.$appAccountToken == token)
            .first() {
            logger.info("AppStoreAuthenticator: found existing user \(token?.uuidString ?? "anon") in \(environment.rawValue)")
            return existing
        }

        let user = User(appAccountToken: token, environment: environment.rawValue, productId: payload.productId ?? "", status: .active)
        try await user.save(on: db)
        logger.info("AppStoreAuthenticator: added user \(token?.uuidString ?? "anon") to database")
        return user
    }

    private func validate(transactionId: String, environment: StoreEnvironment, db: Database, logger: Logger) async throws -> User? {
        let client = try AppStoreServerAPIClient(
            signingKey: iapKey,
            keyId: iapKeyId,
            issuerId: iapIssuerId,
            bundleId: bundleId,
            environment: environment
        )

        logger.info("AppStoreAuthenticator: validating transaction \(transactionId) in \(environment.rawValue)")

        let result = await client.getAllSubscriptionStatuses(transactionId: transactionId, status: [.active, .billingGracePeriod])
        switch result {
        case .success(let response):
            guard let subscriptionGroup = response.data?.first,
                  let lastTransactions = subscriptionGroup.lastTransactions else {
                logger.error("AppStoreAuthenticator: no transactions returned for \(transactionId) in \(environment.rawValue)")
                throw HTTPError(.unauthorized, message: "No active or grace period subscription status found")
            }

            let user = User(appAccountToken: nil, environment: environment.rawValue, productId: "", status: .expired)

            for transaction in lastTransactions {
                guard let signedInfo = transaction.signedTransactionInfo else { continue }
                do {
                    let (token, product) = try await fetchUserAppAccountToken(signedTransactionInfo: signedInfo, environment: environment, logger: logger)
                    user.appAccountToken = token
                    if let product {
                        user.productId = product
                    }
                } catch {
                    continue
                }

                if user.subscriptionStatus != Status.active.rawValue, let status = transaction.status {
                    user.subscriptionStatus = status.rawValue
                }

                if user.appAccountToken != nil, !user.productId.isEmpty {
                    break
                }
            }

            if let existing = try await User.query(on: db)
                .filter(\.$appAccountToken == user.appAccountToken)
                .first() {
                return existing
            }

            try await user.save(on: db)
            return user

        case .failure(let statusCode, _, let apiError, let errorMessage, let causedBy):
            let description = errorMessage ?? apiError.map { String(describing: $0) } ?? "Unknown"
            let cause = causedBy?.localizedDescription ?? "none"
            logger.error("AppStoreAuthenticator: transaction \(transactionId) failed in \(environment.rawValue) - status: \(statusCode ?? 0), error: \(description), caused by: \(cause)")
            if statusCode == 404 {
                throw HTTPError(.notFound)
            }
            throw HTTPError(HTTPResponse.Status(code: statusCode ?? 500, reasonPhrase: errorMessage ?? "Unknown error"))
        }
    }

    private func fetchUserAppAccountToken(signedTransactionInfo: String, environment: StoreEnvironment, logger: Logger) async throws -> (UUID?, String?) {
        let rootCertificates = try loadAppleRootCertificates(logger: logger)
        let verifier = try SignedDataVerifier(
            rootCertificates: rootCertificates,
            bundleId: bundleId,
            appAppleId: appAppleId,
            environment: environment,
            enableOnlineChecks: true
        )

        let response = await verifier.verifyAndDecodeTransaction(signedTransaction: signedTransactionInfo)
        switch response {
        case .valid(let payload):
            return (payload.appAccountToken, payload.productId)
        case .invalid(let error):
            logger.error("AppStoreAuthenticator: verifying transaction failed with error \(error)")
            throw HTTPError(.unauthorized)
        }
    }

    private func loadAppleRootCertificates(logger: Logger) throws -> [Foundation.Data] {
        #if os(Linux)
        return [
            try loadData(url: URL(string: "/app/Resources/AppleComputerRootCertificate.cer"), logger: logger),
            try loadData(url: URL(string: "/app/Resources/AppleIncRootCertificate.cer"), logger: logger),
            try loadData(url: URL(string: "/app/Resources/AppleRootCA-G2.cer"), logger: logger),
            try loadData(url: URL(string: "/app/Resources/AppleRootCA-G3.cer"), logger: logger)
        ].compactMap { $0 }
        #else
        return [
            try loadData(url: Bundle.module.url(forResource: "AppleComputerRootCertificate", withExtension: "cer"), logger: logger),
            try loadData(url: Bundle.module.url(forResource: "AppleIncRootCertificate", withExtension: "cer"), logger: logger),
            try loadData(url: Bundle.module.url(forResource: "AppleRootCA-G2", withExtension: "cer"), logger: logger),
            try loadData(url: Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer"), logger: logger)
        ].compactMap { $0 }
        #endif
    }

    private func loadData(url: URL?, logger: Logger) throws -> Foundation.Data? {
        let fileManager = FileManager.default
        guard let url, fileManager.fileExists(atPath: url.path) else {
            logger.error("AppStoreAuthenticator: missing certificate at \(url?.absoluteString ?? "(nil)")")
            throw HTTPError(.internalServerError)
        }

        guard let data = fileManager.contents(atPath: url.path) else {
            logger.error("AppStoreAuthenticator: unable to read certificate at \(url.absoluteString)")
            return nil
        }
        return data
    }
}
