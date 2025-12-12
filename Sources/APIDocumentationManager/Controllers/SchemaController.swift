//
//  File.swift
//  
//
//  Created by seregin-ma on 09.12.2025.
//

import Vapor
import Fluent

struct SchemaController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let schemas = routes.grouped("api", "v1", "schemas")
        let schema = routes.grouped("api", "v1", "schema")
        // CRUD маршруты
        schemas.get(use: getAll)
        schemas.get(":id", use: getById)
        schemas.post(use: create)
        schemas.put(":id", use: update)
        schemas.delete(":id", use: delete)
        
        // Дополнительные маршруты
        schemas.get(":id", "attributes", use: getAttributes)
        schemas.get("call", ":callId", use: getByAPICall)
        schemas.get("response", ":responseId", use: getByResponse)
        
        schema.get(use: getModelByName)
    }
    
    // Получить все схемы
    func getAll(req: Request) async throws -> [SchemaModel] {
        try await SchemaModel.query(on: req.db)
            .with(\.$attributes)
            .all()
    }
    
    // Получить схему по ID
    func getById(req: Request) async throws -> SchemaModel {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let schema = try await SchemaModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await schema.$attributes.load(on: req.db)
        
        return schema
    }
    
    // Создать новую схему
    func create(req: Request) async throws -> SchemaModel {
        let input = try req.content.decode(CreateSchemaRequest.self)
        
        let schema = SchemaModel(name: input.name)
        try await schema.save(on: req.db)
        
        // Создаем атрибуты, если они переданы
        if let attributes = input.attributes {
            for attrInput in attributes {
                let attribute = SchemaAttributeModel(
                    name: attrInput.name,
                    type: attrInput.type,
                    isNullable: attrInput.isNullable,
                    description: attrInput.description,
                    defaultValue: attrInput.defaultValue,
                    schemaID: schema.id!
                )
                try await attribute.save(on: req.db)
            }
        }
        
        try await schema.$attributes.load(on: req.db)
        return schema
    }
    
    // Обновить схему
    func update(req: Request) async throws -> SchemaModel {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let input = try req.content.decode(UpdateSchemaRequest.self)
        
        guard let schema = try await SchemaModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        if let name = input.name { schema.name = name }
        
        try await schema.save(on: req.db)
        
        // Обновляем атрибуты, если они переданы
        if let attributes = input.attributes {
            // Удаляем старые атрибуты
            try await SchemaAttributeModel.query(on: req.db)
                .filter(\.$schema.$id == schema.id!)
                .delete()
            
            // Создаем новые
            for attrInput in attributes {
                let attribute = SchemaAttributeModel(
                    name: attrInput.name,
                    type: attrInput.type,
                    isNullable: attrInput.isNullable,
                    description: attrInput.description,
                    defaultValue: attrInput.defaultValue,
                    schemaID: schema.id!
                )
                try await attribute.save(on: req.db)
            }
        }
        
        try await schema.$attributes.load(on: req.db)
        return schema
    }
    
    // Удалить схему
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let schema = try await SchemaModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await schema.delete(on: req.db)
        return .noContent
    }
    
    // Получить атрибуты схемы
    func getAttributes(req: Request) async throws -> [SchemaAttributeModel] {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let schema = try await SchemaModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        return try await schema.$attributes.query(on: req.db).all()
    }
    
    // Получить схему по API вызову
    func getByAPICall(req: Request) async throws -> SchemaModel {
        guard let callId = req.parameters.get("callId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let schema = try await SchemaModel.query(on: req.db)
            .filter(\.$apiCall.$id == callId)
            .with(\.$attributes)
            .first()
        else { throw Abort(.notFound, reason: "Schema not found")}
        return schema
    }
    
    // Получить схему по ответу API
    func getByResponse(req: Request) async throws -> [SchemaModel] {
        guard let responseId = req.parameters.get("responseId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let response = try await APIResponseModel.find(responseId, on: req.db) else {
            throw Abort(.notFound, reason: "api response not found")
        }
        try await response.$schemas.load(on: req.db)
        
        for schema in response.schemas {
            try await schema.$attributes.load(on: req.db)
        }
        
        return response.schemas
    }
    
    // Получить Модель по Имени.
    // src__integrations__podcast__models__episode__EpisodeItem
    // /api/v1/schema?name=""
    func getModelByName(req: Request) async throws -> [SchemaModel] {
        let input = try req.query.decode(GetModelNameRequest.self)
        let schema = try await SchemaModel
            .query(on: req.db)
            .filter(\.$name == input.name)
            .with(\.$attributes)
            .all()
        return schema
    }
}

struct GetModelNameRequest: Content {
    let name: String
}
