//
//  User.swift
//
//
//  Created by Ronald Mannak on 1/21/24.
//

import FluentKit
import Foundation
import Hummingbird
import HummingbirdAuth
import AppStoreServerLibrary

final class User: Model, Authenticatable {
    
    static let schema = "user"
    
    @ID(key: .id)
    var id: UUID?
    
    /// app account Id to identify individual users
    /// See https://developer.apple.com/documentation/appstoreserverapi/appaccounttoken
    @Field(key: "appAccountToken")
    var appAccountToken: UUID?
    
    /// Can be Sandbox, Production, Xcode, LocalTesting
    @Field(key: "environment")
    var environment: String
    
    /// The user's active subscription
    @Field(key: "productId")
    var productId: String
    
    /// Subscription status
    /// See https://developer.apple.com/documentation/appstoreserverapi/status
    @Field(key: "subscriptionStatus")
    var subscriptionStatus: Int32
    
    /// If not nil contains the date until user is rate limited
    @Field(key: "blockedUntil")
    var blockedUntil: Date?
    
    /// JWT token
    @Field(key: "jwtToken")
    var jwtToken: String?
    
    /// Overview of requests this user had made
    @Children(for: \.$user)
    var messages: [UserRequest]
    
    internal init() {}
    
    internal init(id: UUID? = nil, appAccountToken: UUID?, environment: String, productId: String, status: AppStoreServerLibrary.Status, token: String? = nil) {
        self.id = id
        self.appAccountToken = appAccountToken
        self.environment = environment
        self.productId = productId
        self.subscriptionStatus = status.rawValue
        self.jwtToken = token
    }
}


extension User {
        
    /// Fetches all messages belonging to user that were made in the last hours and/or minutes
    /// - Parameters:
    ///   - hours: Filters messages in the last x hours
    ///   - minutes: Filters messages in the last x minutes
    ///   - userId: id of the user
    ///   - db: database in the request
    /// - Returns: array of messages in the timeframe provided
    func numberOfRecentRequests(hours: Int, minutes: Int, db: Database) async throws -> Int {
        
        // 1. Get the current date and time
        let now = Date()

        // 2. Calculate the start time
        let hours = Calendar.current.date(byAdding: .hour, value: -hours, to: now) ?? now
        let startTime = Calendar.current.date(byAdding: .minute, value: -minutes, to: hours) ?? hours
        
        // 3. Query messages where the date is greater than one hour ago and the user ID matches
        return try await UserRequest.query(on: db)
            .filter(\.$user.$id == self.requireID())
            .filter(\.$date > startTime)
            .all()
            .count
    }
    
    func numberOfBlockedRequests(db: Database) async throws -> Int {
        return try await UserRequest.query(on: db)
            .filter(\.$user.$id == self.requireID())
            .filter(\.$wasBlocked == true)
            .all()
            .count
    }
}
