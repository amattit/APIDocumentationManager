//
//  File.swift
//  
//
//  Created by seregin-ma on 09.12.2025.
//

import Vapor

public struct ServiceController: RouteCollection {
    public init() {}
    
    public func boot(routes: RoutesBuilder) throws {
        let services = routes.grouped("api", "v1", "services")
        services.get(use: index)
        services.post(use: create)
        services.group(":serviceID") { service in
            service.get(use: get)
            service.put(use: update)
            service.delete(use: delete)
            
            service.group("env") { env in
                env.post(use: createEnvironment)
                env.put(use: updateEnvironment)
            }
        }
    }
    
    /// Получить список сервисов
    public func index(req: Request) async throws -> [ServiceModel] {
        try await ServiceModel.query(on: req.db)
            .with(\.$environments)
            .with(\.$apiCalls)
            .all()
    }
    
    /// Создать сервис
    public func create(req: Request) async throws -> ServiceModel {
        let input = try req.content.decode(CreateServiceRequest.self)
        
        let service = ServiceModel(
            name: input.name,
            version: input.version,
            type: input.type.rawValue,
            owner: input.owner,
            description: input.description
        )
        
        try await service.save(on: req.db)
        return service
    }
    
    public func get(req: Request) async throws -> ServiceModel {
        guard let serviceID = req.parameters.get("serviceID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let service = try await ServiceModel.query(on: req.db)
            .filter(\.$id, .equal, serviceID)
            .with(\.$environments)
            .with(\.$apiCalls, {
                $0.with(\.$requestModel)
                $0.with(\.$parameters)
                $0.with(\.$responses, { $0.with(\.$schemas) } )
            })
            .first() else {
            throw Abort(.notFound)
        }
        return service
    }
    
    public func update(req: Request) async throws -> ServiceModel {
        guard let serviceID = req.parameters.get("serviceID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let input = try req.content.decode(UpdateServiceRequest.self)
        
        guard let service = try await ServiceModel.find(serviceID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        service.name = input.name ?? service.name
        service.version = input.version ?? service.version
        service.type = input.type?.rawValue ?? service.type
        service.owner = input.owner ?? service.owner
        service.description = input.description
        
        try await service.save(on: req.db)
        
        return try await get(req: req)
    }
    
    public func delete(req: Request) async throws -> HTTPStatus {
        guard let serviceID = req.parameters.get("serviceID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let service = try await ServiceModel.find(serviceID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await service.delete(on: req.db)
        return .noContent
    }
    
    public func createEnvironment(req: Request) async throws -> ServiceEnvironmentModel {
        guard let serviceID = req.parameters.get("serviceID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let input = try req.content.decode(CreateServiceEnv.self)
        let env = ServiceEnvironmentModel(
            type: input.type,
            host: input.host,
            serviceID: serviceID
        )
        try await env.save(on: req.db)
        
        return env
    }
    
    public func updateEnvironment(req: Request) async throws -> ServiceEnvironmentModel {
        let input = try req.content.decode(UpdateServiceEnv.self)
        
        guard let env = try await ServiceEnvironmentModel.query(on: req.db)
            .filter(\.$id, .equal, input.id)
            .first()
        else {
            throw Abort(.notFound, reason: "env not found")
        }
        
        env.type = input.type ?? env.type
        env.host = input.host ?? env.host
        
        try await env.save(on: req.db)
        
        return env
    }
}
