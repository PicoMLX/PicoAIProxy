//
//  AppStoreMiddleware.swift
//
//
//  Created by Ronald Mannak on 1/6/24.
//

import Hummingbird
import NIOHTTP1

struct AppStoreMiddleware: HBMiddleware {
    func apply(to request: Hummingbird.HBRequest, next: Hummingbird.HBResponder) -> NIOCore.EventLoopFuture<Hummingbird.HBResponse> {
        
        // 1. If attestation is not enabled in environment variables, we're done
        guard let enabled = HBEnvironment().get("enableAttestation"), enabled == "1" else {
            return next.respond(to: request)
        }
        
        // 2. If passthrough is enabled (e.g. if your app allows users to use their own API keys), check if headers contain OpenAI key
        guard let passthrough = HBEnvironment().get("allowKeyPassthrough"),
              passthrough == "1",
              let org = request.headers["OpenAI-Organization"].first,
              org.hasPrefix("org-") == true,
              let key = request.headers["OpenAI-Key"].first,
              key.hasPrefix("sk-") == true
        else {
            return next.respond(to: request)
        }
        
        // 3. Fetch organization header (that contains attestation)
        // just checks if challenge is in list
//        guard let response = request.headers["OpenAI-Organization"].first, let challenge = attestationController.challenges.filter({ $0.challenge == response }).first else {
//            return request.failure(.unauthorized, message: "App attestation failed")
//        }
//        
        // 4.
        
        return next.respond(to: request)
    }
}
