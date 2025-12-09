// APICallController.swift
import Vapor
import Fluent

struct APICallController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let apiCalls = routes.grouped("api", "v1", "calls")
        let serviceCalls = routes.grouped("api", "v1", "services", ":serviceID" ,"calls")
        
        // CRUD маршруты
        apiCalls.get(use: getAll)
        apiCalls.get(":id", use: getById)
        serviceCalls.post(use: create)
        serviceCalls.put(":id", use: update)
        serviceCalls.delete(":id", use: delete)
        
        // Дополнительные маршруты
        serviceCalls.get(use: getByService)
        serviceCalls.get(":id", "parameters", use: getParameters)
        serviceCalls.get(":id", "responses", use: getResponses)
    }
    
    // Получить все API вызовы
    func getAll(req: Request) async throws -> [APICallModel] {
        try await APICallModel.query(on: req.db)
            .with(\.$parameters)
            .with(\.$responses)
            .with(\.$requestModel)
            .all()
    }
    
    // Получить API вызов по ID
    func getById(req: Request) async throws -> APICallModel {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let apiCall = try await APICallModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await apiCall.$parameters.load(on: req.db)
        try await apiCall.$responses.load(on: req.db)
        try await apiCall.$requestModel.load(on: req.db)
        
        return apiCall
    }
    
    // Создать новый API вызов
    func create(req: Request) async throws -> APICallModel {
        let input = try req.content.decode(CreateAPICallRequest.self)
        
        // Проверяем существует ли сервис
        guard try await ServiceModel.find(input.serviceID, on: req.db) != nil else {
            throw Abort(.notFound, reason: "Service not found")
        }
        
        let apiCall = APICallModel(
            path: input.path,
            method: input.method,
            description: input.description,
            tags: input.tags,
            serviceID: input.serviceID
        )
        
        try await apiCall.save(on: req.db)
        return apiCall
    }
    
    // Обновить API вызов
    func update(req: Request) async throws -> APICallModel {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let input = try req.content.decode(UpdateAPICallRequest.self)
        
        guard let apiCall = try await APICallModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        // Обновляем только переданные поля
        if let path = input.path { apiCall.path = path }
        if let method = input.method { apiCall.method = method }
        if let description = input.description { apiCall.description = description }
        if let tags = input.tags { apiCall.tags = tags }
        if let serviceID = input.serviceID {
            // Проверяем существует ли сервис
            guard try await ServiceModel.find(serviceID, on: req.db) != nil else {
                throw Abort(.notFound, reason: "Service not found")
            }
            apiCall.$service.id = serviceID
        }
        
        try await apiCall.save(on: req.db)
        return apiCall
    }
    
    // Удалить API вызов
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let apiCall = try await APICallModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await apiCall.delete(on: req.db)
        return .noContent
    }
    
    // Получить API вызовы по сервису
    func getByService(req: Request) async throws -> [APICallModel] {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        return try await APICallModel.query(on: req.db)
            .filter(\.$service.$id == serviceId)
            .with(\.$parameters)
            .with(\.$responses)
            .all()
    }
    
    // Получить параметры API вызова
    func getParameters(req: Request) async throws -> [ParameterModel] {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let apiCall = try await APICallModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        return try await apiCall.$parameters.query(on: req.db).all()
    }
    
    // Получить ответы API вызова
    func getResponses(req: Request) async throws -> [APIResponseModel] {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let apiCall = try await APICallModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        
        return try await apiCall.$responses.query(on: req.db)
            .with(\.$schemaModel)
            .all()
    }
}
