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

final class User: Model, HBAuthenticatable {
    static let schema = "user"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "environment")
    var environment: String?
    
    
    @Field(key: "subscription")
    var subscription: String?
    
    internal init() {}

    internal init(id: UUID? = nil, environment: String?, subscription: String?) {
        self.id = id
        self.environment = environment
        self.subscription = subscription
    }

//    internal init(from userRequest: CreateUserRequest) {
//        self.id = nil
//        self.name = userRequest.name
//        self.passwordHash = userRequest.password.map { Bcrypt.hash($0, cost: 12) }
//    }
}

// may store multiple tokens so one user with multiple devices can use 
