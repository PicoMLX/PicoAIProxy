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
    func login(_ request: HBRequest) async throws -> [String: String] {
        
        // 1. Extract app store confirmation from request
        
        // get authenticated user and return
//        let user = try request.authRequire(AttestationResponse.self)
        let payload = JWTPayloadData(
            subject: .init(value: "TEST_VALUE"),
            expiration: .init(value: Date(timeIntervalSinceNow: 12 * 60 * 60)) // 12 hours
        )
        return try [
            "token": self.jwtSigners.sign(payload, kid: self.kid),
        ]
    }
}
