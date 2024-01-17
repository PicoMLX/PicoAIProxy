//
//  AppStoreController.swift
//
//
//  Created by Ronald Mannak on 1/6/24.
//

import Foundation
import Hummingbird
import HummingbirdAuth
import AppStoreServerLibrary
import JWTKit
import NIO

struct AppStoreController {
    
    let jwtSigners: JWTSigners
    let kid: JWKIdentifier

    /// Add routes for /appstore
    func addRoutes(to group: HBRouterGroup) {
        group
            .post("/", use: login)
    }
    
    /// Login user and return JWT
    /// See https://developer.apple.com/documentation/appstoreserverapi
    func login(_ request: HBRequest) async throws -> [String: String] {
        
        // 1. Fetch IAP private key, issuer ID and Key ID
        //    To create a private key, see:
        //    https://developer.apple.com/documentation/appstoreserverapi/creating_api_keys_to_use_with_the_app_store_server_api
        //    and https://developer.apple.com/wwdc23/10143
        guard let iapKey = HBEnvironment().get("IAPPrivateKey"),
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
            throw HBHTTPError(.internalServerError, message: "IAPPrivateKey, IAPIssuerId, IAPKeyId and/or appBundleId environment variables not set")
        }
        
        return try await login(request, iapKey: iapKey,iapKeyId: iapKeyId, iapIssuerId: iapIssuerId, bundleId: bundleId, appAppleId: appAppleId, environment: .production)
    }
    
    func login(_ request: HBRequest, iapKey: String, iapKeyId: String, iapIssuerId: String, bundleId: String, appAppleId: Int64, environment: Environment) async throws -> [String: String] {
        
        // 1. Create App Store API client
        let appStoreClient = try AppStoreServerAPIClient(signingKey: iapKey, keyId: iapKeyId, issuerId: iapIssuerId, bundleId: bundleId, environment: environment)
        
        // Uncomment to test App Store Server API
        /*
        let testResponse = await appStoreClient.requestTestNotification()
        switch testResponse {
        case .success(let response):
            print(response.testNotificationToken ?? "No token")
        case .failure(let statusCode, let rawApiError, let apiError, let errorMessage, let causedBy):
            print("\(statusCode ?? -1): \(errorMessage ?? "Unknown error")")
        }
         */
        
        // 2. The server expects an app store receipt (in the iOS and macOS client app: Bundle.main.appStoreReceiptURL)
        //    However, the receipt is not available when testing in Xcode Sandbox, so the server accepts a
        //    transaction Id as well
        guard let buffer = request.body.buffer, let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
            throw HBHTTPError(.unauthorized)
        }
        let transactionId: String
        if let transaction = ReceiptUtility.extractTransactionId(transactionReceipt: body) {
            transactionId = transaction
        } else if environment == .sandbox {
            transactionId = body
        } else {
            // In case the client is in sandbox and this is the first pass on the server, the id will be empty and trigger
            // login to be called again with environment set to sandbox in the next step
            transactionId = ""
        }
        
        // 3. Use transactionId to fetch subscription from App Store
        let allSubs = await appStoreClient.getAllSubscriptionStatuses(transactionId: transactionId)
        switch allSubs {
        case .success(let response):
            // The App Store server has found the user's subscription
            // TODO: act based on type of subscription
            break
        case .failure(let statusCode, let rawApiError, let apiError, let errorMessage, let causedBy):
            if statusCode == 404 && environment == .production {
                // No transaction wasn't found. Try sandbox for
                return try await login(request, iapKey: iapKey, iapKeyId: iapKeyId, iapIssuerId: iapIssuerId, bundleId: bundleId, appAppleId: appAppleId, environment: .sandbox)
            } else {
                print("\(statusCode ?? -1): \(errorMessage ?? "Unknown error")")
                throw HBHTTPError(.unauthorized)
            }
        }
                
        // Next, we need to fetch the user Id (app account id) so we can implement a rate limiter, track usage
        // and use Id for JWTtoken
        // 4. Get transaction
        let signedTransaction: String
        let transactionResponse = await appStoreClient.getTransactionInfo(transactionId: transactionId)
        switch transactionResponse {
        case .success(let response):
            if let transaction = response.signedTransactionInfo {
                signedTransaction = transaction
            } else {
                throw HBHTTPError(.unauthorized)
            }
        case .failure(let statusCode, let rawApiError, let apiError, let errorMessage, let causedBy):
            print("\(statusCode ?? -1): \(errorMessage ?? "Unknown error")")
            throw HBHTTPError(.unauthorized)
        }
                
        // 5. Get signed transaction
        let appAccountToken: String
        let rootCertificates = try loadAppleRootCertificates() // TODO: add certificates
        let verifier = try SignedDataVerifier(rootCertificates: rootCertificates, bundleId: bundleId, appAppleId: appAppleId, environment: environment, enableOnlineChecks: true)
        let verifyResponse = await verifier.verifyAndDecodeTransaction(signedTransaction: signedTransaction)
        
        switch verifyResponse {
        case .valid(let payload):

            // Fetches app account token set by client app.
            // See https://developer.apple.com/documentation/storekit/product/3791971-purchase
            if let token = payload.appAccountToken?.uuidString {
                // Handle case where app account token is found
                // E.g. add call to rate limiter
                print(token)
                appAccountToken = token
            } else {
                // Handle case when no app account token is found
                appAccountToken = UUID().uuidString
            }
        case .invalid(_):
            throw HBHTTPError(.unauthorized)
        }
        
        // 6. Return JWT token
        let payload = JWTPayloadData(
            subject: .init(value: appAccountToken),
            expiration: .init(value: Date(timeIntervalSinceNow: 12 * 60 * 60)) // 12 hours
        )
        return try [
            "token": self.jwtSigners.sign(payload, kid: self.kid),
        ]
    }
    
    private func loadAppleRootCertificates() throws -> [Foundation.Data] {
        return [
            try loadData(url: Bundle.module.url(forResource: "AppleComputerRootCertificate", withExtension: "cer")),
            try loadData(url: Bundle.module.url(forResource: "AppleIncRootCertificate", withExtension: "cer")),
            try loadData(url: Bundle.module.url(forResource: "AppleRootCA-G2", withExtension: "cer")),
            try loadData(url: Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer")),
        ]
    }
    
    private func loadData(url: URL?) throws -> Foundation.Data {
        guard let url = url,
              let rootData = try? Data(Data(contentsOf: url)) else {
            throw HBHTTPError(.internalServerError)
        }
        return rootData
    }
}
