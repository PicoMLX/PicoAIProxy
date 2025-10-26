import FluentKit
import Foundation
import Hummingbird
import AppStoreServerLibrary

final class User: Model {
    static let schema = "user"

    @ID(key: .id)
    var id: UUID?

    /// App account ID used to identify individual users
    @Field(key: "appAccountToken")
    var appAccountToken: UUID?

    /// Receipt environment (Sandbox, Production, Xcode, LocalTesting)
    @Field(key: "environment")
    var environment: String

    /// The user's active subscription product identifier
    @Field(key: "productId")
    var productId: String

    /// Subscription status as provided by App Store Server API
    @Field(key: "subscriptionStatus")
    var subscriptionStatus: Int32

    /// When not nil contains the time until which the user is blocked
    @Field(key: "blockedUntil")
    var blockedUntil: Date?

    /// Cached JWT token issued to the client
    @Field(key: "jwtToken")
    var jwtToken: String?

    /// Requests executed by this user
    @Children(for: \.$user)
    var messages: [UserRequest]

    init() {}

    init(
        id: UUID? = nil,
        appAccountToken: UUID?,
        environment: String,
        productId: String,
        status: AppStoreServerLibrary.Status,
        token: String? = nil
    ) {
        self.id = id
        self.appAccountToken = appAccountToken
        self.environment = environment
        self.productId = productId
        self.subscriptionStatus = status.rawValue
        self.jwtToken = token
    }
}

extension User: @unchecked Sendable {}

extension User {
    /// Count user's requests in the provided time window
    func numberOfRecentRequests(hours: Int, minutes: Int, db: Database) async throws -> Int {
        let now = Date()
        let hoursAgo = Calendar.current.date(byAdding: .hour, value: -hours, to: now) ?? now
        let start = Calendar.current.date(byAdding: .minute, value: -minutes, to: hoursAgo) ?? hoursAgo

        return try await UserRequest.query(on: db)
            .filter(\.$user.$id == self.requireID())
            .filter(\.$date > start)
            .count()
    }

    func numberOfBlockedRequests(db: Database) async throws -> Int {
        try await UserRequest.query(on: db)
            .filter(\.$user.$id == self.requireID())
            .filter(\.$wasBlocked == true)
            .count()
    }
}
