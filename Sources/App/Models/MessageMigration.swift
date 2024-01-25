//
//  File.swift
//  
//
//  Created by Ronald Mannak on 1/24/24.
//

import Foundation
import FluentKit

struct MessageMigration: AsyncMigration {
    
    func prepare(on database: FluentKit.Database) async throws {
        try await database.schema("message")
            .id()
            .field("date", .datetime, .required)
            .field("model", .string)
            .field("requestLen", .int)
            .field("responseLen", .int)
            .field("token", .string)
            .field("user", .uuid, .required, .references("user", "id"))
            .create()
    }
    
    func revert(on database: FluentKit.Database) async throws {
        try await database.schema("user").delete()
    }
}
