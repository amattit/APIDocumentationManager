//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Fluent
import Vapor

public struct CreateServicesTable: AsyncMigration {
    public func prepare(on database: Database) async throws {
        try await database.schema("services")
            .id()
            .field("name", .string, .required)
            .field("version", .string, .required)
            .field("type", .string, .required)
            .field("department", .string, .required)
            .field("description", .string)
            .field("environments_group", .json) // Для @Group
            .field("owner", .string)
            .field("contact_email", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "name", "version")
            .create()
    }
    
    public func revert(on database: Database) async throws {
        try await database.schema("services").delete()
    }
}

public struct CreateAPIEndpointsTable: AsyncMigration {
    public init() {}
    
    public func prepare(on database: Database) async throws {
        try await database.schema("api_endpoints")
            .id()
            .field("service_id", .uuid, .required, .references("services", "id"))
            .field("path", .string, .required)
            .field("http_method", .string, .required)
            .field("summary", .string)
            .field("description", .string)
            .field("parameters", .array(of: .custom(APIParameter.self)))
            .field("request_body", .string)
            .field("responses", .array(of: .custom(APIResponse.self)))
            .field("business_logic", .string)
            .field("plantuml_diagram", .string)
            .field("dependencies", .array(of: .custom(APICallDependency.self)))
            .field("tags", .array(of: .string))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "service_id", "path", "http_method")
            .create()
    }
    
    public func revert(on database: Database) async throws {
        try await database.schema("api_endpoints").delete()
    }
}
