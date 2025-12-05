//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Vapor

public struct DataModelController: RouteCollection {
    
    public init() {}
    
    public func boot(routes: RoutesBuilder) throws {
        let models = routes.grouped("api", "v1", "models")
        
        models.get(use: getAllModels)
        models.get(":modelId", use: getModel)
        models.get("service", ":serviceId", use: getModelsByService)
        models.get(":modelId", "referencing", use: getReferencingModels)
        models.get("search", use: searchModels)
        
        // Для endpoint'ов
        models.get("endpoint", ":endpointId", "request", use: getEndpointRequestBodyModel)
        models.get("endpoint", ":endpointId", "responses", use: getEndpointResponseModels)
        models.get("endpoint", ":endpointId", "all", use: getAllEndpointModels)
    }
    
    private func getAllModels(req: Request) async throws -> [DataModel] {
        return try await DataModel.query(on: req.db).all()
    }
    
    private func getModel(req: Request) async throws -> DataModel {
        guard let modelId = req.parameters.get("modelId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid model ID")
        }
        
        guard let model = try await DataModel.find(modelId, on: req.db) else {
            throw Abort(.notFound, reason: "Model not found")
        }
        
        return model
    }
    
    private func getModelsByService(req: Request) async throws -> [DataModel] {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        return try await DataModel.query(on: req.db)
            .filter(\.$service.$id, .equal, serviceId)
            .all()
    }
    
    private func getReferencingModels(req: Request) async throws -> [DataModel] {
        guard let modelId = req.parameters.get("modelId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid model ID")
        }
        
        guard let model = try await DataModel.find(modelId, on: req.db) else {
            throw Abort(.notFound, reason: "Model not found")
        }
        
        return try await model.$referencingModels.query(on: req.db).all()
    }
    
    private func searchModels(req: Request) async throws -> [DataModel] {
        guard let query = req.query[String.self, at: "q"] else {
            throw Abort(.badRequest, reason: "Search query required")
        }
        
        return try await DataModel.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$name, .subset(inverse: false) ,query)
                group.filter(\.$title, .subset(inverse: false) ,query)
                group.filter(\.$description, .subset(inverse: false) ,query)
            }
            .all()
    }
    
    private func getEndpointRequestBodyModel(req: Request) async throws -> DataModel {
        guard let endpointId = req.parameters.get("endpointId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid endpoint ID")
        }
        
        guard let endpoint = try await APIEndpoint.find(endpointId, on: req.db) else {
            throw Abort(.notFound, reason: "Endpoint not found")
        }
        
        guard let model = try await endpoint.$requestBodyModel.get(on: req.db) else {
            throw Abort(.notFound, reason: "Model not found")
        }
        return model
    }
    
    private func getEndpointResponseModels(req: Request) async throws -> [DataModel] {
        guard let endpointId = req.parameters.get("endpointId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid endpoint ID")
        }
        
        // Сначала получаем endpoint
        guard let endpoint = try await APIEndpoint.find(endpointId, on: req.db) else {
            throw Abort(.notFound, reason: "Endpoint not found")
        }
        
        return try await endpoint.$responseModels.get(on: req.db)
        // Собираем ID моделей из ответов
//        var modelIds: [UUID] = []
//        for response in endpoint.responses {
//            if let modelId = response.dataModelId {
//                modelIds.append(modelId)
//            }
//        }
//        
//        if modelIds.isEmpty {
//            return []
//        }
//        
//        // Получаем модели по ID
//        return try await DataModel.query(on: req.db)
//            .filter(\.$id, .subset(inverse: false), modelIds)
//            .all()
    }
    
    struct EndpointModelsResponse: Content {
        let requestBodyModel: DataModel?
        let responseModels: [DataModel]
        let parameterModels: [DataModel]
    }
    private func getAllEndpointModels(req: Request) async throws -> EndpointModelsResponse {
        
        guard let endpointId = req.parameters.get("endpointId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid endpoint ID")
        }
        
        guard let endpoint = try await APIEndpoint.find(endpointId, on: req.db) else {
            throw Abort(.notFound, reason: "Endpoint not found")
        }
        
        let requestBodyModel = try await endpoint.$requestBodyModel.get(on: req.db)
        
        // Получаем модели из ответов
        var responseModels: [DataModel] = []
        for response in endpoint.responses {
            if let modelId = response.dataModelId,
               let model = try await DataModel.find(modelId, on: req.db) {
                responseModels.append(model)
            }
        }
        
        // Получаем модели из параметров
        var parameterModels: [DataModel] = []
        for param in endpoint.parameters {
            if let modelId = param.dataModelId,
               let model = try await DataModel.find(modelId, on: req.db) {
                parameterModels.append(model)
            }
        }
        
        return EndpointModelsResponse(
            requestBodyModel: requestBodyModel,
            responseModels: responseModels,
            parameterModels: parameterModels
        )
    }
}
