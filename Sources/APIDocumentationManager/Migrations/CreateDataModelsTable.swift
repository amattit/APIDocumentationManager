//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Fluent

public struct CreateDataModelsTable: AsyncMigration {
    public init() {}
    
    public func prepare(on database: Database) async throws {
        // 1. Создаем таблицу data_models
        try await database.schema("data_models")
            .id()
            .field("service_id", .uuid, .required, .references("services", "id", onDelete: .cascade))
            .field("endpoint_id", .uuid, .required, .references("api_endpoints", "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("title", .string)
            .field("description", .string)
            .field("type", .string, .required)
            .field("properties", .array(of: .json))
            .field("required_properties", .array(of: .string))
            .field("examples", .array(of: .json))
            .field("is_reference", .bool, .required)
            .field("referenced_model_name", .string)
//            .field("referenced_model_id", .uuid, .references("data_models", "id", onDelete: .setNull))
            .field("tags", .array(of: .string))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("openapi_ref", .string)
            .field("source", .string, .required)
            .unique(on: "service_id", "name")
            .create()
        
        // 2. Создаем таблицу для отношений many-to-many
        try await database.schema("data_model_relationships")
            .id()
            .field("parent_model_id", .uuid, .required, .references("data_models", "id", onDelete: .cascade))
            .field("child_model_id", .uuid, .required, .references("data_models", "id", onDelete: .cascade))
            .field("relationship_type", .string, .required)
            .field("property_name", .string)
            .field("description", .string)
            .field("created_at", .datetime)
            .unique(on: "parent_model_id", "child_model_id", "property_name")
            .create()
        
        // 3. Добавляем внешний ключ для APIEndpoint.request_body_model_id
        try await database.schema("api_endpoints")
            .field("request_body_model_id", .uuid, .references("data_models", "id", onDelete: .setNull))
            .update()
    }
    
    public func revert(on database: Database) async throws {
        // В обратном порядке удаляем таблицы
        try await database.schema("api_endpoints")
            .deleteField("request_body_model_id")
            .update()
        
        try await database.schema("data_model_relationships").delete()
        try await database.schema("data_models").delete()
    }
}
