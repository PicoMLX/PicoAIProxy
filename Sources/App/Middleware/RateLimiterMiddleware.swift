//
//  RateLimiterMiddleware.swift
//  
//
//  Created by Ronald Mannak on 1/23/24.
//

import Foundation
import FluentKit
import Hummingbird

struct RateLimiterMiddleware: HBAsyncMiddleware {
    
    func apply(to request: Hummingbird.HBRequest, next: Hummingbird.HBResponder) async throws -> Hummingbird.HBResponse {
                
        // 1. Fetch user and create new message
        let user = try request.authRequire(User.self)
        let message = try Message(date: Date(), userId: user.requireID())
                
        // 3. Save message
        try await message.save(on: request.db)
        
        // 4.
        let lastMinute = try await Message.itemsLast(hours: 0, minutes: 1, userId: user.requireID(), db: request.db)
        let lastHour = try await Message.itemsLast(hours: 1, minutes: 0, userId: user.requireID(), db: request.db)
        
        print("--- Last minute: \(lastMinute.count) messages")
        print("--- Last hour: \(lastHour.count) messages")
        // TO DO: let user set limits via environment variables
        
        return try await next.respond(to: request)
    }
}
