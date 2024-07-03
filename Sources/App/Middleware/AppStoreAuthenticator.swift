//
//  AppStoreAuthenticator.swift
//
//
//  Created by Ronald Mannak on 1/21/24.
//

import Foundation
import FluentKit
import Hummingbird
import HummingbirdAuth
import AppStoreServerLibrary
#if os(Linux)
import FoundationNetworking
#endif

/// Defines a custom authenticator for App Store transactions
struct AppStoreAuthenticator: HBAsyncAuthenticator {
   
    // Properties to hold App Store credentials and app-specific information
    let iapKey: String
    let iapIssuerId: String
    let iapKeyId: String
    let bundleId: String
    let appAppleId: Int64
    
    /// Initializer to load necessary credentials and configuration from environment variables
    init() throws {
        
        // Fetch IAP private key, issuer ID, and Key ID from environment variables
        // Information about creating a private key is available in Apple's documentation
        // Failing to find required environment variables results in an error
        // To create a private key, see:
        //    https://developer.apple.com/documentation/appstoreserverapi/creating_api_keys_to_use_with_the_app_store_server_api
        //    and https://developer.apple.com/wwdc23/10143
        guard let iapKey = HBEnvironment().get("IAPPrivateKey")?.replacingOccurrences(of: "\\\\n", with: "\n"),
              !iapKey.isEmpty,
              let iapIssuerId = HBEnvironment().get("IAPIssuerId"),
              !iapIssuerId.isEmpty,
              let iapKeyId = HBEnvironment().get("IAPKeyId"),
              !iapKeyId.isEmpty,
              let bundleId = HBEnvironment().get("appBundleId"),
              !bundleId.isEmpty,
              let appAppleIdString = HBEnvironment().get("appAppleId"),
              let appAppleId = Int64(appAppleIdString)
        else {
            // If the environment variables are not set, SwiftProxyAIServer will throw an internal server error.
            // Check your server's logs for the message below
            throw HBHTTPError(.internalServerError, message: "IAPPrivateKey, IAPIssuerId, IAPKeyId and/or appBundleId, appAppleId environment variable(s) not set")
        }
        self.iapKey = iapKey
        self.iapIssuerId = iapIssuerId
        self.iapKeyId = iapKeyId
        self.bundleId = bundleId
        self.appAppleId = appAppleId
    }
    
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
            request.logger.error("AppStoreAuthenticator: /appstore invoked with empty body")
            throw HBHTTPError(.badRequest)
        }
        
        if let payload = try await validateJWS(jws: body, environment: .production, request: request) {
            // Validated production transaction
            return try await addUser(request: request, payload: payload, environment: .production)
            
        } else if let payload = try await validateJWS(jws: body, environment: .sandbox, request: request) {
            // Validated sandbox transaction
            return try await addUser(request: request, payload: payload, environment: .sandbox)
            
        } else if let payload = try await validateJWS(jws: body, environment: .xcode, request: request) {
            // Validated Xcode transaction
            return try await addUser(request: request, payload: payload, environment: .xcode)
            
        } else {
            // Use Store Kit 1 app receipts

            // Extract transaction ID
            guard let id = ReceiptUtility.extractTransactionId(appReceipt: body) else {
                throw HBHTTPError(.unauthorized)
            }
            let transactionId = id
            
            // Try validating the transaction in production environment first
            // If not found (404 error), retries in the sandbox environment for TestFlight users
            do {
                return try await validate(request, transactionId: transactionId, environment: .production)
            } catch let error as HBHTTPError where error.status == .notFound {
                request.logger.error("AppStoreAuthenticator: Caught HBHTTPError.notFound. Validating transaction in sandbox.")
                return try await validate(request, transactionId: transactionId, environment: .sandbox)
            }
        }
    }
    
    // MARK: - Store Kit 2 JWS authentication
    
    /// Validates JWS string and checks expiry date
    /// - Parameters:
    ///   - jws: the jws string from the client app
    ///   - environment: Either .production, .sandbox, or .xcode
    ///   - request: HBRequest
    /// - Returns: Payload if successful or nil if jws has a different environment than provided
    private func validateJWS(jws: String, environment: Environment, request: HBRequest) async throws -> JWSTransactionDecodedPayload? {

        // 1. Set up JWT verifier
        let rootCertificates = try loadAppleRootCertificates(request: request)
        let verifier = try SignedDataVerifier(rootCertificates: rootCertificates, bundleId: bundleId, appAppleId: appAppleId, environment: environment, enableOnlineChecks: true)
        request.logger.debug("environment: \(environment)")

        // 2. Parse JWS transaction
        let verifyResponse = await verifier.verifyAndDecodeTransaction(signedTransaction: jws)
        request.logger.debug("verifyResponse: \(verifyResponse)")
        
        switch verifyResponse {
        case .valid(let payload):
            
            // Check expiry date
            if let date = payload.expiresDate, date < Date() {
                request.logger.error("Subscription of user \(payload.appAccountToken?.uuidString ?? "anon") expired on \(date)")
                throw HBHTTPError(.unauthorized)
            }
            
            // Check revocation date (for refunds and family removal)
            if let date = payload.revocationDate, date < Date() {
                request.logger.error("Subscription of user \(payload.appAccountToken?.uuidString ?? "anon") was revoked on \(date)")
                throw HBHTTPError(.unauthorized)
            }
            
            request.logger.info("AppStoreAuthenticator: validated tx for user \(payload.appAccountToken?.uuidString ?? "anon") in \(environment)")
            return payload
            
        case .invalid(let error):
            
            switch error {
            case .INVALID_JWT_FORMAT:
                request.logger.error("validateJWS failed: invalid JWT format")
            case .INVALID_CERTIFICATE:
                request.logger.error("validateJWS failed: invalid certificate")
            case .VERIFICATION_FAILURE:
                request.logger.error("validateJWS failed: verification failed")
            case .INVALID_APP_IDENTIFIER:
                request.logger.error("validateJWS failed: invalid app identifier")
            case .INVALID_ENVIRONMENT:
                // Return nil so caller can try a different environment
                return nil
            }
            // We don't want to throw an error here as it may be caused by an environment mismatch
            // throw HBHTTPError(.unauthorized)
            return nil
        }
    }
    
    /// Finds existing user or creates new user in database
    /// - Parameters:
    ///   - request: HBRequest
    ///   - payload: JWS payload
    ///   - environment: Either .production, .sandbox, or .xcode
    /// - Returns: user
    private func addUser(request: HBRequest, payload: JWSTransactionDecodedPayload, environment: Environment) async throws -> User {
        
        // 1. create user
        let user = User(appAccountToken: nil, environment: environment.rawValue, productId: "", status: .expired)
        user.appAccountToken = payload.appAccountToken
        if let productId = payload.productId {
            user.productId = productId
        }
                
        // 2. If user doesn't exist, add to database
        //    Otherwise, return existing user
        if let existingUser = try await User.query(on: request.db)
            .filter(\.$appAccountToken == user.appAccountToken)
            .first() {
            request.logger.info("addUser found existing user \(payload.appAccountToken?.uuidString ?? "anon") in database")
            return existingUser
        }
        try await user.save(on: request.db)
        request.logger.info("addUser added user \(payload.appAccountToken?.uuidString ?? "anon") to database")
        return user
    }
    
    // MARK: - Pre-Store Kit 2 App Store Receipt authentication
    
    /// Validates the transaction ID with the App Store and returns a User if successful
    /// - Parameters:
    ///   - request: http request
    ///   - transactionId: transaction Id. Can be original transaction Id
    ///   - environment: e.g. .sandbox
    /// - Returns: new or existing user
    private func validate(_ request: HBRequest, transactionId: String, environment: Environment) async throws -> User? {
        
        // 1. Create App Store API client
        let appStoreClient = try AppStoreServerAPIClient(signingKey: iapKey, keyId: iapKeyId, issuerId: iapIssuerId, bundleId: bundleId, environment: environment)
        
        request.logger.info("AppStoreAuthenticator: Created API Client for keyId: \(iapKeyId), issuer: \(iapIssuerId), bundleId: \(bundleId), env: \(environment.rawValue)")
        
        // 3. create user
        let user = User(appAccountToken: nil, environment: environment.rawValue, productId: "", status: .expired)
        
        // 4. Use transactionId to fetch active subscriptions from App Store
        let allSubs = await appStoreClient.getAllSubscriptionStatuses(transactionId: transactionId, status: [.active, .billingGracePeriod])
        switch allSubs {
        case .success(let response):
            
            request.logger.info("AppStoreAuthenticator: TxId: \(transactionId) \(environment.rawValue): number of data: \(response.data?.count ?? 0)")
            
            // SwiftProxyServer assumes app has a single subscription group
            guard let subscriptionGroup = response.data?.first,
                  let lastTransactions = subscriptionGroup.lastTransactions else {
                request.logger.error("AppStoreAuthenticator: TxId: \(transactionId) \(environment.rawValue): Get all subscriptions succeeded but returned no transactions. No subscription group or no last transactions in \(environment.rawValue) for \(transactionId)")
                throw HBHTTPError(.unauthorized, message: "No active or grace period subscription status found")
            }
            
            request.logger.info("AppStoreAuthenticator: TxId: \(transactionId) \(environment.rawValue): Found \(lastTransactions.count) transactions")
            
            // Loop through the transactions in the subscription group
            for transaction in lastTransactions {
                
                request.logger.info("AppStoreAuthenticator: Parsing transaction \(transaction.originalTransactionId ?? "(No original tx id)"), status: \(transaction.status?.description ?? "(no known status)")")
                
                guard let signedTransactionInfo = transaction.signedTransactionInfo else { continue }
                
                let appAccountToken: UUID?
                let productId: String?
                do {
                    let (token, product) = try await fetchUserAppAccountToken(signedTransactionInfo: signedTransactionInfo, environment: environment, request: request)
                    appAccountToken = token
                    productId = product
                } catch {
                    // Skip to next product in case of an error
                    continue
                }

                if let productId {
                    user.productId = productId
                }
                
                if let appAccountToken {
                    user.appAccountToken = appAccountToken
                }
                
                // We're only saving one subscription, an active one if available.
                // Update user.status. Make sure we don't overwrite it if the status is already .active
                if user.subscriptionStatus != Status.active.rawValue, let status = transaction.status {
                    user.subscriptionStatus = status.rawValue
                }
                
                request.logger.info("AppStoreAuthenticator: TxId: \(transactionId) \(environment.rawValue): Found token \(appAccountToken?.uuidString ?? "(no token)") for \(productId ?? "(no product ID)") in \(environment.rawValue)")
                            
                if let _ = user.appAccountToken, !user.productId.isEmpty {
                    // We have all information
                    break
                }
            }
            
        case .failure(let statusCode, let rawApiError, let apiError, let errorMessage, let causedBy):
            
            request.logger.error("AppStoreAuthenticator: TxId: \(transactionId) \(environment.rawValue): Get all subscriptions returned an error: code \(statusCode ?? 0), api error: \(rawApiError ?? 0), error msg: \(errorMessage ?? ""), caused by: \(causedBy?.localizedDescription ?? "")")
            
            if statusCode == 404 {
                // No transaction was found.
                request.logger.error("AppStoreAuthenticator: TxId: \(transactionId) \(environment.rawValue) not found. Error: \(statusCode ?? -1): \(errorMessage ?? "Unknown error"), \(String(describing: rawApiError)) \(String(describing: apiError)), \(String(describing: causedBy))")
                throw HBHTTPError(.notFound)
            } else {
                // Other error occurred
                request.logger.error("AppStoreAuthenticator: TxId: \(transactionId) \(environment.rawValue): Get all subscriptions failed in \(environment.rawValue) for \(transactionId). Error: \(statusCode ?? -1): \(errorMessage ?? "Unknown error"), \(String(describing: rawApiError)) \(String(describing: apiError)), \(String(describing: causedBy))")
                throw HBHTTPError(HTTPResponseStatus(statusCode: statusCode ?? 500, reasonPhrase: errorMessage ?? "Unknown error"))
            }
        }
        
        // 5. If user doesn't exist, add to database
        //    Otherwise, return existing user
        if let existingUser = try await User.query(on: request.db)
            .filter(\.$appAccountToken == user.appAccountToken)
            .first() {
            return existingUser
        }
        try await user.save(on: request.db)
        return user
    }
    
    /// Fetches app account token set by client app and productID
    /// Note: Token is nil when client app doesn't set appAccountToken during the purchase
    /// See https://developer.apple.com/documentation/storekit/product/3791971-purchase
    /// - Parameters:
    ///   - signedTransactionInfo: SignedTransactionInfo fetched by getAllSubscriptionStatuses
    ///   - environment: E.g. .sandbox
    ///   - request: The request (to access logger)
    /// - Returns: Tuple of optional appAccountToken and optional productID
    private func fetchUserAppAccountToken(signedTransactionInfo: String, environment: Environment, request: HBRequest) async throws -> (UUID?, String?) {
                
        // 1. Set up JWT verifier
        let rootCertificates = try loadAppleRootCertificates(request: request)
        let verifier = try SignedDataVerifier(rootCertificates: rootCertificates, bundleId: bundleId, appAppleId: appAppleId, environment: environment, enableOnlineChecks: true)
        
        // 5. Parse signed transaction
        let verifyResponse = await verifier.verifyAndDecodeTransaction(signedTransaction: signedTransactionInfo)
        
        switch verifyResponse {
        case .valid(let payload):

            return (payload.appAccountToken, payload.productId)

        case .invalid(let error):
                        
            request.logger.error("Verifying transaction failed. Error: \(error)")
            throw HBHTTPError(.unauthorized)
        }
    }
    
    private func loadAppleRootCertificates(request: HBRequest) throws -> [Foundation.Data] {
        #if os(Linux)
        // Linux doesn't have app bundles, so we're copying the certificates in the Dockerfile to /app/Resources and load them manually
        return [
            try loadData(url: URL(string: "/app/Resources/AppleComputerRootCertificate.cer"), request: request),
            try loadData(url: URL(string: "/app/Resources/AppleIncRootCertificate.cer"), request: request),
            try loadData(url: URL(string: "/app/Resources/AppleRootCA-G2.cer"), request: request),
            try loadData(url: URL(string: "/app/Resources/AppleRootCA-G3.cer"), request: request),
        ].compactMap { $0 }
        #else
        return [
            try loadData(url: Bundle.module.url(forResource: "AppleComputerRootCertificate", withExtension: "cer"), request: request),
            try loadData(url: Bundle.module.url(forResource: "AppleIncRootCertificate", withExtension: "cer"), request: request),
            try loadData(url: Bundle.module.url(forResource: "AppleRootCA-G2", withExtension: "cer"), request: request),
            try loadData(url: Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer"), request: request),
        ].compactMap { $0 }
        #endif
    }
    
    private func loadData(url: URL?, request: HBRequest) throws -> Foundation.Data? {
        let fs = FileManager()
        guard let url = url, fs.fileExists(atPath: url.path) else {
            request.logger.error("File missing: \(url?.absoluteString ?? "invalid url")")
            throw HBHTTPError(.internalServerError)
        }
                
        guard let data = fs.contents(atPath: url.path) else {
            request.logger.error("Can't read data from \(url.absoluteString)")
            return nil
        }
        return data
    }

    internal func base64URLToBase64(_ encodedString: String) -> String {
        let replacedString = encodedString
            .replacingOccurrences(of: "/", with: "+")
            .replacingOccurrences(of: "_", with: "-")
        if (replacedString.count % 4 != 0) {
            return replacedString + String(repeating: "=", count: 4 - replacedString.count % 4)
        }
        return replacedString
    }
}


private struct RawValueCodingKey: CodingKey {

    private static let keysToRawKeys = ["environment": "rawEnvironment", "receiptType": "rawReceiptType",  "consumptionStatus": "rawConsumptionStatus", "platform": "rawPlatform", "deliveryStatus": "rawDeliveryStatus", "accountTenure": "rawAccountTenure", "playTime": "rawPlayTime", "lifetimeDollarsRefunded": "rawLifetimeDollarsRefunded", "lifetimeDollarsPurchased": "rawLifetimeDollarsPurchased", "userStatus": "rawUserStatus", "status": "rawStatus", "expirationIntent": "rawExpirationIntent", "priceIncreaseStatus": "rawPriceIncreaseStatus", "offerType": "rawOfferType", "type": "rawType", "inAppOwnershipType": "rawInAppOwnershipType", "revocationReason": "rawRevocationReason", "transactionReason": "rawTransactionReason", "offerDiscountType": "rawOfferDiscountType", "notificationType": "rawNotificationType", "subtype": "rawSubtype", "sendAttemptResult": "rawSendAttemptResult", "autoRenewStatus": "rawAutoRenewStatus"]
    private static let rawKeysToKeys = ["rawEnvironment": "environment", "rawReceiptType": "receiptType",  "rawConsumptionStatus": "consumptionStatus", "rawPlatform": "platform", "rawDeliveryStatus": "deliveryStatus", "rawAccountTenure": "accountTenure", "rawPlayTime": "playTime", "rawLifetimeDollarsRefunded": "lifetimeDollarsRefunded", "rawLifetimeDollarsPurchased": "lifetimeDollarsPurchased", "rawUserStatus": "userStatus", "rawStatus": "status", "rawExpirationIntent": "expirationIntent", "rawPriceIncreaseStatus": "priceIncreaseStatus", "rawOfferType": "offerType", "rawType": "type", "rawInAppOwnershipType": "inAppOwnershipType", "rawRevocationReason": "revocationReason", "rawTransactionReason": "transactionReason", "rawOfferDiscountType": "offerDiscountType", "rawNotificationType": "notificationType", "rawSubtype": "subtype", "rawSendAttemptResult": "sendAttemptResult", "rawAutoRenewStatus": "autoRenewStatus"]

    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    init(decodingKey: CodingKey) {
        let decodingKeyString = decodingKey.stringValue
        self.stringValue = RawValueCodingKey.keysToRawKeys[decodingKeyString, default: decodingKeyString]
        self.intValue = nil
    }

    init(encodingKey: CodingKey) {
        let encodingKeyString = encodingKey.stringValue
        self.stringValue = RawValueCodingKey.rawKeysToKeys[encodingKeyString, default: encodingKeyString]
        self.intValue = nil
    }
}

struct JWTHeader: Decodable, Encodable {
    public var alg: String?
    public var x5c: [String]?
}

