//
//  File.swift
//  
//
//  Created by Ronald Mannak on 12/20/23.
//

import AppStoreServerLibrary
/*
struct AppStore {
    
    let issuerId = "99b16628-15e4-4668-972b-eeff55eeff55"
    let keyId = "ABCDEFGHIJ"
    let bundleId = "com.example"
    let encodedKey = try! String(contentsOfFile: "/path/to/key/SubscriptionKey_ABCDEFGHIJ.p8")
    let environment = Environment.sandbox
    
    func run() async throws {
        // try! used for example purposes only
        let client = try! AppStoreServerAPIClient(signingKey: encodedKey, keyId: keyId, issuerId: issuerId, bundleId: bundleId, environment: environment)
        
        let response = await client.requestTestNotification()
        switch response {
        case .success(let response):
            print(response.testNotificationToken)
        case .failure(let errorCode, let apiError, let causedBy):
            print(errorCode)
            print(apiError)
            print(causedBy)
        }
    }
    
}
*/
