//
//  AttestationController.swift
//
//
//  Created by Ronald Mannak on 12/24/23.
//

import Foundation
import Hummingbird
import HummingbirdAuth
import AppAttest
/*
// TODO: refactor to HBAsyncAuthenticator?
class AttestationController {
        
    var challenges = [AttestationChallenge]()
    
    /// Add routes for /attestation path
    /// - Parameter group: router group
    func addRoutes(to group: HBRouterGroup) {
        group
            .get("/", use: generateNonce)
            .post("/", use: verifyNonce)
    }
    
    /// Generates one-time use random challenge the client app should sign
    /// - Parameter request: incoming request
    /// - Returns: challenge 
    func generateNonce(_ request: HBRequest) throws -> AttestationChallenge {
        let challenge = AttestationChallenge()
        challenges.append(challenge)
        return challenge
    }
    
    func verifyNonce(_ request: HBRequest) throws -> HBResponse {
        guard let response = try? request.decode(as: AttestationResponse.self), 
              let challengeStruct = challenges.filter({ $0.id == response.id }).first,
              let challenge = Data(base64Encoded: challengeStruct.challenge),
              let attestation = Data(base64Encoded: response.response),
              let keyID = response.id.uuidString.data(using: .utf8) // which keyID is this??
        else {
            return HBResponse(status: .badRequest)
        }
        
        guard let teamId = HBEnvironment().get("appTeamID"), 
              let bundleId = HBEnvironment().get("appBundleID"),
              !teamId.isEmpty, !bundleId.isEmpty
        else {
            return HBResponse(status: .internalServerError)
        }
        
        let request = AppAttest.AttestationRequest(attestation: attestation, keyID: keyID)
        let appID = AppAttest.AppID(teamID: teamId, bundleID: bundleId)

        // Verify the attestation
        do {
            let result = try AppAttest.verifyAttestation(challenge: challenge, request: request, appID: appID)
            // TODO: finish verifying attestation
        } catch {
            print(error.localizedDescription)
            return HBResponse(status: .unauthorized)
        }
        
        return HBResponse(status: .accepted)
    }
}
*/
