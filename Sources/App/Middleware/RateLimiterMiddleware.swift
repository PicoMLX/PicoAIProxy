//
//  RateLimiterMiddleware.swift
//
//
//  Created by Ronald Mannak on 1/23/24.
//

import FluentKit
import Foundation
import Hummingbird
import HummingbirdFluent

/// The rate limiter is designed to mitigate the risk of excessive usage for a given key.
///
/// The rate limiter is off by default. To enable the rate limiter, set the value of environment variable `enableRateLimiter` to 1 (default is 0)
/// ... (description retained)
struct RateLimiterMiddleware: RouterMiddleware {
    typealias Context = ProxyRequestContext

    let fluent: Fluent

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if request.uri.path.hasPrefix("/appstore") {
            return try await next(request, context)
        }

        let environment = Environment()
        guard environment.get("enableRateLimiter") == "1" else {
            context.logger.info("Rate limiter disabled. Skipping enforcement for request \(request.uri.path)")
            return try await next(request, context)
        }

        let user = try context.requireIdentity()
        let db = fluent.db()

        let lastMinute = try await user.numberOfRecentRequests(hours: 0, minutes: 1, db: db)
        let lastHour = try await user.numberOfRecentRequests(hours: 1, minutes: 0, db: db)
        let blockedRequests = try await user.numberOfBlockedRequests(db: db)
        let now = Date()
        var blockUntil: Date?

        if let blockedDate = user.blockedUntil, blockedDate == .distantFuture {
            blockUntil = blockedDate
        } else if user.appAccountToken != nil {
            if let limit = rateLimit(for: "userPermanentBlock", environment: environment), blockedRequests >= limit {
                blockUntil = .distantFuture
            } else if let limit = rateLimit(for: "userHourlyRateLimit", environment: environment), lastHour >= limit {
                blockUntil = Calendar.current.date(byAdding: .hour, value: 1, to: now)
            } else if let limit = rateLimit(for: "userMinuteRateLimit", environment: environment), lastMinute >= limit {
                blockUntil = Calendar.current.date(byAdding: .minute, value: 5, to: now)
            }
        } else {
            if let limit = rateLimit(for: "anonPermanentBlock", environment: environment), blockedRequests >= limit {
                blockUntil = .distantFuture
            } else if let limit = rateLimit(for: "anonHourlyRateLimit", environment: environment), lastHour >= limit {
                blockUntil = Calendar.current.date(byAdding: .hour, value: 1, to: now)
            } else if let limit = rateLimit(for: "anonMinuteRateLimit", environment: environment), lastMinute >= limit {
                blockUntil = Calendar.current.date(byAdding: .minute, value: 5, to: now)
            }
        }

        context.logger.info("User \(user.appAccountToken?.uuidString ?? "anon"). Requests last minute: \(lastMinute). Requests last hour: \(lastHour)")

        if let blockUntil {
            if let alreadyBlockedUntil = user.blockedUntil, blockUntil > alreadyBlockedUntil {
                user.blockedUntil = blockUntil
                try await user.save(on: db)
            } else if user.blockedUntil == nil {
                user.blockedUntil = blockUntil
                try await user.save(on: db)
            }

            let userRequest = try UserRequest(endpoint: request.uri.path, wasBlocked: true, userId: user.requireID())
            try await userRequest.save(on: db)
            context.logger.info("User \(user.appAccountToken?.uuidString ?? "anon") requested \(request.uri.path) and is blocked until \(user.blockedUntil?.description ?? "(no date)")")

            if let blockedUntil = user.blockedUntil,
               blockedUntil != .distantFuture,
               let minutes = Calendar.current.dateComponents([.minute], from: now, to: blockedUntil).minute {
                throw HTTPError(.tooManyRequests, message: "Rate limit reached. Try again in \(minutes) minutes")
            } else {
                throw HTTPError(.tooManyRequests, message: "Rate limit reached")
            }
        } else {
            let userRequest = try UserRequest(endpoint: request.uri.path, wasBlocked: false, userId: user.requireID())
            try await userRequest.save(on: db)
            context.logger.info("User \(user.appAccountToken?.uuidString ?? "anon") requested \(request.uri.path)")
            return try await next(request, context)
        }
    }

    private func rateLimit(for key: String, environment: Environment) -> Int? {
        guard let value = environment.get(key), let limit = Int(value), limit > 0 else {
            return nil
        }
        return limit
    }
}
