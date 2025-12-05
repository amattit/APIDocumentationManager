//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Fluent
import Vapor

public struct CreateServicesTable: AsyncMigration {
    public init() {}
    public func prepare(on database: Database) async throws {
        try await database.schema("services")
            .id()
            .field("name", .string, .required)
            .field("version", .string, .required)
            .field("type", .string, .required)
            .field("department", .string, .required)
            .field("description", .string)
            .field("environments_list", .array(of: .json)) // Для @Group
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
            .field("parameters", .array(of: .json))
            .field("request_body_schema_ref", .string)
//            .field("request_body_model_id", .uuid)
            .field("request_body_required", .bool)
            .field("request_body_description", .string)
            .field("responses", .array(of: .json))
            .field("business_logic", .string)
            .field("plantuml_diagram", .string)
            .field("dependencies", .array(of: .json))
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
