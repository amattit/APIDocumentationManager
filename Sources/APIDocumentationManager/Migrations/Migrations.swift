//
//  File.swift
//  
//
//  Created by seregin-ma on 09.12.2025.
//

import Fluent

struct CreateServiceModelMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("services")
            .id()
            .field("name", .string, .required)
            .field("version", .string, .required)
            .field("type", .string, .required)
            .field("owner", .string, .required)
            .field("description", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("services").delete()
    }
}

struct CreateServiceEnvironmentModelMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("service_environments")
            .id()
            .field("type", .string, .required)
            .field("host", .string, .required)
            .field("description", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("service_id", .uuid, .required, .references("services", "id", onDelete: .cascade))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("service_environments").delete()
    }
}

struct CreateAPICallModelMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("api_calls")
            .id()
            .field("path", .string, .required)
            .field("method", .string, .required)
            .field("description", .string, .required)
            .field("tags", .json, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("service_id", .uuid, .required, .references("services", "id", onDelete: .cascade))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("api_calls").delete()
    }
}

struct CreateParameterModelMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("parameters")
            .id()
            .field("name", .string, .required)
            .field("type", .string, .required)
            .field("location", .string, .required)
            .field("required", .bool, .required)
            .field("description", .string)
            .field("example", .string)
            .field("api_call_id", .uuid, .required, .references("api_calls", "id", onDelete: .cascade))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("parameters").delete()
    }
}

struct CreateAPIResponseModelMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("api_responses")
            .id()
            .field("status_code", .int, .required)
            .field("description", .string)
            .field("content_type", .string, .required)
            .field("examples", .json)
            .field("headers", .json)
            .field("api_call_id", .uuid, .required, .references("api_calls", "id", onDelete: .cascade))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("api_responses").delete()
    }
}

struct CreateSchemaModelMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("schemas")
            .id()
            .field("name", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("api_response_id", .uuid, .references("api_responses", "id", onDelete: .cascade))
            .field("api_call_id", .uuid, .references("api_calls", "id", onDelete: .cascade))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("schemas").delete()
    }
}

struct CreateSchemaAttributeModelMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("schema_attributes")
            .id()
            .field("name", .string, .required)
            .field("type", .string, .required)
            .field("is_nullable", .bool, .required)
            .field("description", .string, .required)
            .field("default_value", .string)
            .field("schema_id", .uuid, .required, .references("schemas", "id", onDelete: .cascade))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("schema_attributes").delete()
    }
}
