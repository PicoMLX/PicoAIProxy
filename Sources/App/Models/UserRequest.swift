//
//  UserRequest.swift
//  
//
//  Created by Ronald Mannak on 1/23/24.
//

import Foundation
import FluentKit

/// Every request will be logged for the rate limiter middleware
final class UserRequest: Model {
    
    static let schema = "userrequest"

    @ID(key: .id)
    var id: UUID?

    /// Date and time of the request
    @Field(key: "date")
    var date: Date
    
    /// Endpoint called in this request
    @Field(key: "endpoint")
    var endpoint: String
    
    /// If true, this request was blocked by the rate limiter
    @Field(key: "wasBlocked")
    var wasBlocked: Bool
    
    /// Model called. Currently not used
    @Field(key: "model")
    var model: String?
    
    /// Length of the request in characters (not tokens). Currently not used
    @Field(key: "requestLen")
    var requestLen: Int?
    
    /// Length of the response in characters (not tokens). Currently not used
    @Field(key: "responseLen")
    var responseLen: Int?
    
    /// User who made the request
    @Parent(key: "user")
    var user: User

    internal init() {}
    
    internal init(endpoint: String, wasBlocked: Bool, model: String? = nil,  requestLen: Int? = nil, responseLen: Int? = nil, userId: UUID) {
        self.id = id
        self.date = Date()
        self.endpoint = endpoint
        self.wasBlocked = wasBlocked
        self.model = model
        self.requestLen = requestLen
        self.responseLen = responseLen
        self.$user.id = userId
    }
}
