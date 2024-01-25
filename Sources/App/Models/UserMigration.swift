//
//  UserMigration.swift
//
//
//  Created by Ronald Mannak on 1/21/24.
//

import Foundation
import FluentKit

struct UserMigration: AsyncMigration {
    
    func prepare(on database: FluentKit.Database) async throws {
        try await database.schema("user")
            .id()
            .field("appAccountId", .uuid)
            .field("environment", .string, .required)
            .field("productId", .string, .required)
            .field("status", .int32, .required)
            .field("token", .string)
            .unique(on: "appAccountId")
            .create()
    }
    
    func revert(on database: FluentKit.Database) async throws {
        try await database.schema("user").delete()
    }
}
