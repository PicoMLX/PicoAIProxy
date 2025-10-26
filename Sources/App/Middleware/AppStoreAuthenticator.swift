//
//  AppStoreAuthenticator.swift
//
//
//  Created by Ronald Mannak on 1/21/24.
//

import FluentKit
import Foundation
import Hummingbird
import HummingbirdFluent
import HTTPTypes
import AppStoreServerLibrary
typealias StoreEnvironment = AppStoreServerLibrary.Environment
#if os(Linux)
import FoundationNetworking
#endif

/// Defines a custom authenticator for App Store transactions
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
        let processEnvironment = Hummingbird.Environment()
        guard let iapKey = processEnvironment.get("IAPPrivateKey")?.replacingOccurrences(of: "\\\n", with: "\n"),
              !iapKey.isEmpty,
              let iapIssuerId = processEnvironment.get("IAPIssuerId"),
              !iapIssuerId.isEmpty,
              let iapKeyId = processEnvironment.get("IAPKeyId"),
              !iapKeyId.isEmpty,
              let bundleId = processEnvironment.get("appBundleId"),
              !bundleId.isEmpty,
              let appAppleIdString = processEnvironment.get("appAppleId"),
              let appAppleId = Int64(appAppleIdString)
        else {
            throw HTTPError(.internalServerError, message: "IAPPrivateKey, IAPIssuerId, IAPKeyId and/or appBundleId, appAppleId environment variable(s) not set")
        }
        self.iapKey = iapKey
        self.iapIssuerId = iapIssuerId
        self.iapKeyId = iapKeyId
        self.bundleId = bundleId
        self.appAppleId = appAppleId
    }
<<<<<<< Updated upstream
    
    /// Authenticates incoming requests based on App Store receipt or transaction ID
    /// - Parameter request: HBRequest
    /// - Returns: User model if app store receipt is valid
    func authenticate(request: HBRequest) async throws -> User? {
        
        // 1. The server expects an app store receipt
        //    (in the iOS and macOS client app: Bundle.main.appStoreReceiptURL)
        //    However, the receipt is not available when testing in Xcode Sandbox,
        //    so the server accepts a transaction Id in sandbox mode as well
        let request = try await request.collateBody().get()
        guard let buffer = request.body.buffer, let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
            request.logger.error("/appstore invoked without app store receipt or transaction id in body")
            throw HBHTTPError(.badRequest)
        }
        
        request.logger.info("parsing body: \(body.count) bytes")
        
        // 2. Attempts to extract the transactionId from the receipt
        //    If unsuccessful, assumes the body itself is a transaction ID (useful for sandbox testing)
        guard let transactionId = ReceiptUtility.extractTransactionId(appReceipt: body) else {
            // Body can't be parsed because body isn't the app receipt
            // Retry in sandbox mode
            request.logger.error("Body is not an app receipt. Trying to validate in sandbox. Body: (\(body)")
            return try await validate(request, transactionId: body, environment: .sandbox)
        }
        
        request.logger.info("Found transaction ID \(transactionId)")

        // 3. Tries to validate the transaction in production environment first
        //    If not found (404 error), retries in the sandbox environment for TestFlight users
        do {
            return try await validate(request, transactionId: transactionId, environment: .production)
        } catch let error as HBHTTPError where error.status == .notFound {
            request.logger.info("Caught HBHTTPError.notFound. Validating transaction in sandbox.")
            return try await validate(request, transactionId: transactionId, environment: .sandbox)
        }
    }
    
    
    /// Validates the transaction ID with the App Store and returns a User if successful
    /// - Parameters:
    ///   - request: http request
    ///   - transactionId: transaction Id. Can be original transaction Id
    ///   - environment: e.g. .sandbox
    /// - Returns: new or existing user
    private func validate(_ request: HBRequest, transactionId: String, environment: Environment) async throws -> User? {
        
        // 1. Create App Store API client
        let appStoreClient = try AppStoreServerAPIClient(signingKey: iapKey, keyId: iapKeyId, issuerId: iapIssuerId, bundleId: bundleId, environment: environment)
        
        request.logger.info("Created API Client for keyId: \(iapKeyId), issuer: \(iapIssuerId), bundleId: \(bundleId), env: \(environment.rawValue)")
        
        // 3. create user
        let user = User(appAccountToken: nil, environment: environment.rawValue, productId: "", status: .expired)
        
        // 4. Use transactionId to fetch active subscriptions from App Store
        let allSubs = await appStoreClient.getAllSubscriptionStatuses(transactionId: transactionId, status: [.active, .billingGracePeriod])
        switch allSubs {
        case .success(let response):
            
//            request.logger.info("TxId: \(transactionId) \(environment.rawValue): Successfully received response from getAllSubscriptionStatuses. Response: \(response)")
            request.logger.info("TxId: \(transactionId) \(environment.rawValue): number of data: \(response.data?.count ?? 0)")
            
            // SwiftProxyServer assumes app has a single subscription group
            guard let subscriptionGroup = response.data?.first,
                  let lastTransactions = subscriptionGroup.lastTransactions else {
                request.logger.error("TxId: \(transactionId) \(environment.rawValue): Get all subscriptions succeeded but returned no transactions. No subscription group or no last transactions in \(environment.rawValue) for \(transactionId)")
                throw HBHTTPError(.unauthorized, message: "No active or grace period subscription status found")
            }
            
            request.logger.info("TxId: \(transactionId) \(environment.rawValue): Found \(lastTransactions.count) transactions")
            
            // Loop through the transactions in the subscription group
            for transaction in lastTransactions {
                
                request.logger.info("Parsing transaction \(transaction.originalTransactionId ?? "(No original tx id)"), status: \(transaction.status?.description ?? "(no known status)")")
                
=======

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if !request.uri.path.hasPrefix("/appstore") {
            return try await next(request, context)
        }

        var request = request
        let body = try await collectBodyString(&request, context: context)
        let logger = context.logger
        let db = fluent.db()

        if let payload = try await validateJWS(jws: body, environment: StoreEnvironment.production, logger: logger) {
            let user = try await addUser(payload: payload, environment: StoreEnvironment.production, db: db, logger: logger)
            var context = context
            context.identity = user
            return try await next(request, context)
        } else if let payload = try await validateJWS(jws: body, environment: StoreEnvironment.sandbox, logger: logger) {
            let user = try await addUser(payload: payload, environment: StoreEnvironment.sandbox, db: db, logger: logger)
            var context = context
            context.identity = user
            return try await next(request, context)
        } else if let payload = try await validateJWS(jws: body, environment: StoreEnvironment.xcode, logger: logger) {
            let user = try await addUser(payload: payload, environment: StoreEnvironment.xcode, db: db, logger: logger)
            var context = context
            context.identity = user
            return try await next(request, context)
        }

        guard let transactionId = ReceiptUtility.extractTransactionId(appReceipt: body) else {
            throw HTTPError(.unauthorized)
        }

        do {
            if let user = try await validate(transactionId: transactionId, environment: StoreEnvironment.production, db: db, logger: logger) {
                var context = context
                context.identity = user
                return try await next(request, context)
            }
        } catch let error as HTTPError where error.status == .notFound {
            logger.error("AppStoreAuthenticator: Production lookup failed. Falling back to sandbox for transaction \(transactionId)")
            if let user = try await validate(transactionId: transactionId, environment: StoreEnvironment.sandbox, db: db, logger: logger) {
                var context = context
                context.identity = user
                return try await next(request, context)
            }
        }

        throw HTTPError(.unauthorized)
    }

    private func collectBodyString(_ request: inout Request, context: Context) async throws -> String {
        let buffer = try await request.collectBody(upTo: context.maxUploadSize)
        guard let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
            throw HTTPError(.badRequest)
        }
        return body
    }

    private func validateJWS(jws: String, environment: StoreEnvironment, logger: Logger) async throws -> JWSTransactionDecodedPayload? {
        let rootCertificates = try loadAppleRootCertificates(logger: logger)
        let verifier = try SignedDataVerifier(rootCertificates: rootCertificates, bundleId: bundleId, appAppleId: appAppleId, environment: environment, enableOnlineChecks: true)
        logger.debug("AppStoreAuthenticator: validating JWS in \(environment)")

        let verifyResponse = await verifier.verifyAndDecodeTransaction(signedTransaction: jws)
        switch verifyResponse {
        case .valid(let payload):
            if let date = payload.expiresDate, date < Date() {
                logger.error("Subscription for \(payload.appAccountToken?.uuidString ?? "anon") expired on \(date)")
                throw HTTPError(.unauthorized)
            }
            if let date = payload.revocationDate, date < Date() {
                logger.error("Subscription for \(payload.appAccountToken?.uuidString ?? "anon") revoked on \(date)")
                throw HTTPError(.unauthorized)
            }
            logger.info("AppStoreAuthenticator: validated JWS for user \(payload.appAccountToken?.uuidString ?? "anon") in \(environment)")
            return payload

        case .invalid(let error):
            switch error {
            case .INVALID_JWT_FORMAT:
                logger.error("AppStoreAuthenticator: invalid JWT format")
            case .INVALID_CERTIFICATE:
                logger.error("AppStoreAuthenticator: invalid certificate")
            case .VERIFICATION_FAILURE:
                logger.error("AppStoreAuthenticator: verification failure")
            case .INVALID_APP_IDENTIFIER:
                logger.error("AppStoreAuthenticator: invalid app identifier")
            case .INVALID_ENVIRONMENT:
                return nil
            }
            return nil
        }
    }

    private func addUser(payload: JWSTransactionDecodedPayload, environment: StoreEnvironment, db: Database, logger: Logger) async throws -> User {
        let user = User(appAccountToken: nil, environment: environment.rawValue, productId: "", status: .expired)
        user.appAccountToken = payload.appAccountToken
        if let productId = payload.productId {
            user.productId = productId
        }

        if let existingUser = try await User.query(on: db)
            .filter(\.$appAccountToken == user.appAccountToken)
            .first() {
            logger.info("AppStoreAuthenticator: found existing user \(payload.appAccountToken?.uuidString ?? "anon")")
            return existingUser
        }

        try await user.save(on: db)
        logger.info("AppStoreAuthenticator: added user \(payload.appAccountToken?.uuidString ?? "anon") to database")
        return user
    }

    private func validate(transactionId: String, environment: StoreEnvironment, db: Database, logger: Logger) async throws -> User? {
        let appStoreClient = try AppStoreServerAPIClient(signingKey: iapKey, keyId: iapKeyId, issuerId: iapIssuerId, bundleId: bundleId, environment: environment)

        logger.info("AppStoreAuthenticator: validating transaction \(transactionId) in \(environment.rawValue)")

        let result = await appStoreClient.getAllSubscriptionStatuses(transactionId: transactionId, status: [.active, .billingGracePeriod])
        switch result {
        case .success(let response):
            guard let subscriptionGroup = response.data?.first,
                  let lastTransactions = subscriptionGroup.lastTransactions else {
                logger.error("AppStoreAuthenticator: no transactions returned for \(transactionId) in \(environment.rawValue)")
                throw HTTPError(.unauthorized, message: "No active or grace period subscription status found")
            }

            let user = User(appAccountToken: nil, environment: environment.rawValue, productId: "", status: .expired)
            for transaction in lastTransactions {
>>>>>>> Stashed changes
                guard let signedTransactionInfo = transaction.signedTransactionInfo else { continue }
                do {
                    let (token, product) = try await fetchUserAppAccountToken(signedTransactionInfo: signedTransactionInfo, environment: environment, logger: logger)
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
<<<<<<< Updated upstream
                
                request.logger.info("TxId: \(transactionId) \(environment.rawValue): Found token \(appAccountToken?.uuidString ?? "(no token)") for \(productId ?? "(no product ID)") in \(environment.rawValue)")
                            
                if let _ = user.appAccountToken, !user.productId.isEmpty {
                    // We have all information
                    break
                }
            }
            
        case .failure(let statusCode, let rawApiError, let apiError, let errorMessage, let causedBy):
            
            request.logger.error("TxId: \(transactionId) \(environment.rawValue): Get all subscriptions returned an error: code \(statusCode ?? 0), api error: \(rawApiError ?? 0), error msg: \(errorMessage ?? ""), caused by: \(causedBy?.localizedDescription ?? "")")
            
            if statusCode == 404 {
                // No transaction was found.
                request.logger.error("TxId: \(transactionId) \(environment.rawValue) not found. Error: \(statusCode ?? -1): \(errorMessage ?? "Unknown error"), \(String(describing: rawApiError)) \(String(describing: apiError)), \(String(describing: causedBy))")
                throw HBHTTPError(.notFound)
            } else {
                // Other error occurred
                request.logger.error("TxId: \(transactionId) \(environment.rawValue): Get all subscriptions failed in \(environment.rawValue) for \(transactionId). Error: \(statusCode ?? -1): \(errorMessage ?? "Unknown error"), \(String(describing: rawApiError)) \(String(describing: apiError)), \(String(describing: causedBy))")
                throw HBHTTPError(HTTPResponseStatus(statusCode: statusCode ?? 500, reasonPhrase: errorMessage ?? "Unknown error"))
=======

                if user.appAccountToken != nil, !user.productId.isEmpty {
                    break
                }
            }

            if let existingUser = try await User.query(on: db)
                .filter(\.$appAccountToken == user.appAccountToken)
                .first() {
                return existingUser
>>>>>>> Stashed changes
            }
            try await user.save(on: db)
            return user

        case .failure(let statusCode, _, let apiError, let errorMessage, let causedBy):
            let errorDescription = errorMessage ?? apiError.map { String(describing: $0) } ?? "Unknown"
            let causeDescription = causedBy?.localizedDescription ?? "none"
            logger.error("AppStoreAuthenticator: transaction \(transactionId) failed in \(environment.rawValue) - status: \(statusCode ?? 0), error: \(errorDescription), caused by: \(causeDescription)")
            if statusCode == 404 {
                throw HTTPError(.notFound)
            }
            throw HTTPError(HTTPResponse.Status(code: statusCode ?? 500, reasonPhrase: errorMessage ?? "Unknown error"))
        }
    }

    private func fetchUserAppAccountToken(signedTransactionInfo: String, environment: StoreEnvironment, logger: Logger) async throws -> (UUID?, String?) {
        let rootCertificates = try loadAppleRootCertificates(logger: logger)
        let verifier = try SignedDataVerifier(rootCertificates: rootCertificates, bundleId: bundleId, appAppleId: appAppleId, environment: environment, enableOnlineChecks: true)
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
            try loadData(url: URL(string: "/app/Resources/AppleRootCA-G3.cer"), logger: logger),
        ].compactMap { $0 }
        #else
        return [
            try loadData(url: Bundle.module.url(forResource: "AppleComputerRootCertificate", withExtension: "cer"), logger: logger),
            try loadData(url: Bundle.module.url(forResource: "AppleIncRootCertificate", withExtension: "cer"), logger: logger),
            try loadData(url: Bundle.module.url(forResource: "AppleRootCA-G2", withExtension: "cer"), logger: logger),
            try loadData(url: Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer"), logger: logger),
        ].compactMap { $0 }
        #endif
    }

    private func loadData(url: URL?, logger: Logger) throws -> Foundation.Data? {
        let fileManager = FileManager()
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
