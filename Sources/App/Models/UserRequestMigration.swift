//
//  File.swift
//  
//
//  Created by Ronald Mannak on 1/24/24.
//

import Foundation
import FluentKit

struct UserRequestMigration: AsyncMigration {
    
    func prepare(on database: FluentKit.Database) async throws {
        try await database.schema("userrequest")
            .id()
            .field("date", .datetime, .required)
            .field("endpoint", .string)
            .field("model", .string)
            .field("wasBlocked", .bool)
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
