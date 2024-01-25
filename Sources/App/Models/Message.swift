//
//  File.swift
//  
//
//  Created by Ronald Mannak on 1/23/24.
//

import Foundation
import FluentKit

final class Message: Model {
    static let schema = "message"

    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "date")
    var date: Date
    
    @Field(key: "model")
    var model: String?
    
    /// Length of the request in characters (not tokens)
    @Field(key: "requestLen")
    var requestLen: Int?
    
    /// Length of the response in characters (not tokens)
    @Field(key: "responseLen")
    var responseLen: Int?
    
    @Parent(key: "user")
    var user: User

    internal init() {}
    
    internal init(date: Date, model: String? = nil, requestLen: Int? = nil, responseLen: Int? = nil, userId: UUID) {
        self.id = id
        self.date = date
        self.model = model
        self.requestLen = requestLen
        self.responseLen = responseLen
        self.$user.id = userId
    }
}

extension Message {
//    func itemsLast(hours: Int, db: Database) async throws -> [Message] {
//        
//        // 1. Get the current date and time
//        let now = Date()
//        
//        // 2. Calculate the time one hour ago
//        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -hours, to: now) ?? now
//        
//        // 3. Query messages where the date is greater than one hour ago
//        return try await Message.query(on: db)
//            .filter(\.$date > oneHourAgo)
//            .all()
//    }
    
    static func itemsLast(hours: Int, minutes: Int, userId: UUID, db: Database) async throws -> [Message] {
        
        // 1. Get the current date and time
        let now = Date()

        // 2. Calculate the start time
        let hours = Calendar.current.date(byAdding: .hour, value: -hours, to: now) ?? now
        let startTime = Calendar.current.date(byAdding: .minute, value: -minutes, to: hours) ?? hours
        
        // 3. Query messages where the date is greater than one hour ago and the user ID matches
        return try await Message.query(on: db)
            .filter(\.$date > startTime)
            .filter(\.$user.$id == userId) // Assuming the foreign key property in Message is user.id
            .all()
    }
}
