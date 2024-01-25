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

final class User: Model, HBAuthenticatable {
    static let schema = "user"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "appAccountId")
    var appAccountId: UUID?
    
    @Field(key: "environment")
    var environment: String
    
    @Field(key: "productId")
    var productId: String
    
    @Field(key: "status")
    var status: Int32
    
    @Field(key: "token")
    var token: String?
    
    @Children(for: \.$user)
    var messages: [Message]
    
    internal init() {}
    
    internal init(id: UUID? = nil, appAccountId: UUID?, environment: String, productId: String, status: AppStoreServerLibrary.Status, token: String? = nil) {
        self.id = id
        self.appAccountId = appAccountId
        self.environment = environment
        self.productId = productId
        self.status = status.rawValue
        self.token = token
    }
}
