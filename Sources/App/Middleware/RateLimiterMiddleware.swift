//
//  RateLimiterMiddleware.swift
//
//
//  Created by Ronald Mannak on 1/23/24.
//

import Foundation
import FluentKit
import Hummingbird

/// The rate limiter is designed to mitigate the risk of excessive usage for a given key.
///
/// The rate limiter is off by default. To enable the rate limiter, set the value of environment variable `enableRateLimiter` to 1 (default is 0)
///
/// It allows developers to configure usage thresholds on two levels:
///
/// 1. Maximum messages per minute: The default limit is 15 messages.
/// 2. Maximum messages per hour: The default limit is 50 messages.
///
/// User identification is based on their app account token. 
/// See for more info:
/// https://developer.apple.com/documentation/storekit/product/purchaseoption/3749440-appaccounttoken
///
/// The system also provides separate rate limits for users who don't have an app account token,
/// catering to scenarios where the client application may not assign these tokens.
/// The default rate limits for these users are set higher, at 60 messages per minute and 200 messages per hour.
/// It's recommended to tailor these default values based on the proportion of users operating without an app account token.
///
/// Users will be blocked permanently if the number of blocked messages exceeds environment variable `userPermanentBlock` 
/// for users with an app account token or `anonPermanentBlock` for all users without a token combined.
/// The default value is 50 for `userPermanentBlock` and `anonPermanentBlock`
///
/// To disable any or multiple rules, remove the environment variable or its value (i.e. `userPermanentBlock`, `userHourlyRateLimit`, `userMinuteRateLimit`,
/// `anonPermanentBlock`, `anonHourlyRateLimit`, and `anonMinuteRateLimit`)
///
/// Note that the current version of Pico AI Proxy doesn't store data persistently. Blocks and message request history will be reset
/// whenever Pico AI Proxy is deployed.
///
/// For more precise control, such as downgrading the model from GPT-4 to GPT-3.5 when a user exceeds a specific limit,
/// you need to handle this logic on the client side
struct RateLimiterMiddleware: HBAsyncMiddleware {
    
    func apply(to request: Hummingbird.HBRequest, next: Hummingbird.HBResponder) async throws -> Hummingbird.HBResponse {

        // 1. Fetch user
        let user = try request.authRequire(User.self)        
        
        // 2. If rate limiter isn't enabled, we're done
        guard let enableUserRateLimiter = HBEnvironment().get("enableRateLimiter"), enableUserRateLimiter == "1" else {
            
            let userRequest = try? UserRequest(endpoint: request.uri.path, wasBlocked: false, userId: user.requireID())
            try? await userRequest?.save(on: request.db)
            request.logger.info("User \(user.appAccountToken?.uuidString ?? "anon") request \(request.uri.path). Rate limiter is disabled")
            return try await next.respond(to: request)
            
        }
        
        // 3. Fetch user request history
        let lastMinute = try await user.numberOfRecentRequests(hours: 0, minutes: 1, db: request.db)
        let lastHour = try await user.numberOfRecentRequests(hours: 1, minutes: 0, db: request.db)
        let blockedRequests = try await user.numberOfBlockedRequests(db: request.db)
        let now = Date()
        var blockUntil: Date? = nil
        
        if let blockedDate = user.blockedUntil, blockedDate == Date.distantFuture {
            
            // 4. If user is blocked permanently, set blockUntil so the request gets logged
            blockUntil = blockedDate
            
        } else if let _ = user.appAccountToken {
            
            // 5. Check rate limit for users with an app account token
            
            if let limit = rateLimit(for: "userPermanentBlock"), blockedRequests >= limit {
                
                // 5.a User will be blocked permanently if the number of blocked requests exceeds userPermanentBlock
                blockUntil = Date.distantFuture
                
            } else if let limit = rateLimit(for: "userHourlyRateLimit"), lastHour >= limit {
                
                // 5.b User will be blocked for one hour if they exceeded hourly limit
                blockUntil = Calendar.current.date(byAdding: .hour, value: 1, to: now)

            } else if let limit = rateLimit(for: "userMinuteRateLimit"), lastHour >= limit {

                // 5.c User will be blocked for one 5 minutes if they exceeded minute limit
                blockUntil = Calendar.current.date(byAdding: .minute, value: 5, to: now)

            }
            
        } else {
            
            // 6. Check rate limit for users with an app account token (anonymous users)
            
            if let limit = rateLimit(for: "anonPermanentBlock"), blockedRequests >= limit {
                
                // 6.a All anonymous users will be blocked
                blockUntil = Date.distantFuture
                
            } else if let limit = rateLimit(for: "anonHourlyRateLimit"), lastHour >= limit {
                
                // 6.c User will be blocked for one hour if they exceeded hourly limit
                blockUntil = Calendar.current.date(byAdding: .hour, value: 1, to: now)

            } else if let limit = rateLimit(for: "anonMinuteRateLimit"), lastHour >= limit {

                // 6.d User will be blocked for one 5 minutes if they exceeded minute limit
                blockUntil = Calendar.current.date(byAdding: .minute, value: 5, to: now)

            }
                        
        }
        
        request.logger.info("User \(user.appAccountToken?.uuidString ?? "anon"). Requests last minute: \(lastMinute). Requests last hour: \(lastHour)")

        // 7. If request is blocked, register request attempt
        
        if let blockUntil {
            
            // 8.a Update blockedUntil if new block is further into the future
            if let alreadyBlockedUntil = user.blockedUntil, blockUntil > alreadyBlockedUntil {
                user.blockedUntil = blockUntil
                try await user.save(on: request.db)
            }
            
            // 8.b Log request
            let userRequest = try UserRequest(endpoint: request.uri.path, wasBlocked: true, userId: user.requireID())
            try await userRequest.save(on: request.db)
            request.logger.info("User \(user.appAccountToken?.uuidString ?? "anon") requested \(request.uri.path) and is blocked until \(user.blockedUntil?.description ?? "(no date)")")
            
            // 8.c Reject request by throwing too many requests error
            if let blockedUntil = user.blockedUntil,
               blockedUntil != Date.distantFuture,
               let minutes = Calendar.current.dateComponents([.minute], from: now, to: blockedUntil).minute {
                throw HBHTTPError(.tooManyRequests, message: "Rate limit reached. Try again in \(minutes) minutes")
            } else {
                throw HBHTTPError(.tooManyRequests, message: "Rate limit reached")
            }
            
        } else {
            
            // 9. Request was allowed. Log request and forward request to the next step
            let userRequest = try UserRequest(endpoint: request.uri.path, wasBlocked: false, userId: user.requireID())
            try await userRequest.save(on: request.db)
            request.logger.info("User \(user.appAccountToken?.uuidString ?? "anon") requested \(request.uri.path)")
                        
            return try await next.respond(to: request)
        }
    }
    
    private func rateLimit(for key: String) -> Int? {
        guard let userHourlyRateLimiter = HBEnvironment().get(key),
              let limit = Int(userHourlyRateLimiter),
              limit > 0 else {
            // This limit is not set, we're done
            return nil
        }
              
        return limit
    }
}
