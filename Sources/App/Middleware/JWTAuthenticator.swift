//
//  JWTAuthenticator.swift
//
//  Created by Ronald Mannak on 1/8/24.
//

import FluentKit
import Foundation
import Hummingbird
import HummingbirdFluent
import HTTPTypes
@preconcurrency import JWTKit

struct JWTPayloadData: JWTPayload, Equatable {
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
    }

    var subject: SubjectClaim
    var expiration: ExpirationClaim

    func verify(using signer: JWTSigner) throws {
        try self.expiration.verifyNotExpired()
    }
}

struct JWTAuthenticator: RouterMiddleware {
    typealias Context = ProxyRequestContext

    let fluent: Fluent
    let allowPassthrough: Bool
    let jwtSigners: JWTSigners

    init(fluent: Fluent, allowPassthrough: Bool) {
        self.fluent = fluent
        self.allowPassthrough = allowPassthrough
        self.jwtSigners = JWTSigners()
    }

    func useSigner(_ signer: JWTSigner, kid: JWKIdentifier) {
        self.jwtSigners.use(signer, kid: kid)
    }

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if request.uri.path.hasPrefix("/appstore") {
            return try await next(request, context)
        }

        guard let token = bearerToken(from: request) else {
            context.logger.error("No jwtToken found")
            throw HTTPError(.unauthorized)
        }

        if allowPassthrough,
           let organizationHeader = HTTPField.Name("OpenAI-Organization"),
           let organization = request.headers[organizationHeader],
           organization.hasPrefix("org-"),
           token.hasPrefix("sk-") {
            context.logger.info("OpenAI API key Passthrough")
            return try await next(request, context)
        }

        let payload: JWTPayloadData
        do {
            payload = try jwtSigners.verify(token, as: JWTPayloadData.self)
        } catch {
            context.logger.error("Invalid jwtToken received")
            throw HTTPError(.unauthorized)
        }

        let appAccountToken = UUID(uuidString: payload.subject.value)
        guard let user = try await User.query(on: fluent.db())
            .filter(\.$appAccountToken == appAccountToken)
            .first() else {
            context.logger.error("User with app account token \(appAccountToken?.uuidString ?? "anon") not found in database")
            throw HTTPError(.proxyAuthenticationRequired)
        }

        var context = context
        context.identity = user
        context.logger.info("Verified user with app account token \(user.appAccountToken?.uuidString ?? "anon")")
        return try await next(request, context)
    }

    private func bearerToken(from request: Request) -> String? {
        guard let header = request.headers[.authorization] else { return nil }
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let scheme = parts[0]
        if scheme.caseInsensitiveCompare("Bearer") == .orderedSame {
            return String(parts[1])
        }
        return nil
    }
}
