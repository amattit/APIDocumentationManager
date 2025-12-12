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
        apiCalls.post(use: create)
        apiCalls.put(":id", use: update)
        apiCalls.delete(":id", use: delete)
        
        // CUD responses
        apiCalls.post(":id", "responses", use: createResponse)
        apiCalls.post("responses", ":responseID", use: updateResponse)
        apiCalls.delete("responses", ":responseID", use: deleteResponse)
        apiCalls.post("link-schema-response", use: linkSchemaWithResponse)
        apiCalls.post("link-schema-request", use: linkSchemaRequestWithAPI)
        
        //CUD parameters
        apiCalls.post(":id", "parameters", use: createParameters)
        apiCalls.post(":id", "parameter", use: createParameter)
        apiCalls.put(":id", "parameter", ":parameterID", use: updateParameter)
        apiCalls.post(":id", "parameter", ":parameterID", use: deleteParameter)
        
        // Дополнительные маршруты
        serviceCalls.get(use: getByService)
        serviceCalls.get(":id", "parameters", use: getParameters)
        serviceCalls.get(":id", "responses", use: getResponses)
    }
    
    // Получить все API вызовы
    func getAll(req: Request) async throws -> [APICallModel] {
        try await APICallModel.query(on: req.db)
            .with(\.$parameters)
            .with(\.$responses, {res in
                res.with(\.$schemas, {
                    $0.with(\.$attributes)
                })
            })
            .with(\.$requestModel, { $0.with(\.$attributes) })
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
        for response in apiCall.responses {
            try await response.$schemas.load(on: req.db)
            for schema in response.schemas {
                try await schema.$attributes.load(on: req.db)
            }
        }
        try await apiCall.$requestModel.load(on: req.db)
        try await apiCall.requestModel?.$attributes.load(on: req.db)
        
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
    
    func createResponse(req: Request) async throws -> APIResponseModel {
        guard let apiCallID = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let input = try req.content.decode(CreateResponseDTO.self)
        
        let response = APIResponseModel(
            statusCode: input.statusCode,
            description: input.description,
            contentType: input.contentType, 
            examples: input.examples,
            headers: input.headers,
            apiCallID: apiCallID
        )
        
        try await response.save(on: req.db)
        return response
    }
    
    func updateResponse(req: Request) async throws -> APIResponseModel {
        guard let responseID = req.parameters.get("responseID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let input = try req.content.decode(UpdateResponseDTO.self)
        
        guard let response = try await APIResponseModel.query(on: req.db)
            .filter(\.$id == responseID)
            .first()
        else {
            throw Abort(.notFound, reason: "response not found")
        }
        
        response.statusCode = input.statusCode ?? response.statusCode
        response.description = input.description ?? response.description
        response.contentType = input.contentType ?? response.contentType
        response.examples = input.examples ?? response.examples
        response.headers = input.headers ?? response.headers
        
        try await response.save(on: req.db)
        return response
    }
    
    func deleteResponse(req: Request) async throws -> HTTPStatus {
        guard let responseID = req.parameters.get("responseID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard let response = try await APIResponseModel.query(on: req.db)
            .filter(\.$id == responseID)
            .first()
        else {
            throw Abort(.notFound, reason: "response not found")
        }
        
        try await response.delete(on: req.db)
        
        return .noContent
    }
    
    func createParameter(req: Request) async throws -> HTTPStatus {
        guard let apiCallID = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let input = try req.content.decode(CreateParameterDTO.self)
        
        let parameter = ParameterModel(
            name: input.name,
            type: input.type,
            location: input.location,
            required: input.required,
            description: input.description,
            example: input.example,
            apiCallID: apiCallID
        )
        
        try await parameter.save(on: req.db)
        return .noContent
    }
    
    func createParameters(req: Request) async throws -> HTTPStatus {
        guard let apiCallID = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let input = try req.content.decode([CreateParameterDTO].self)
        let params = input.map { input in
            ParameterModel(
                name: input.name,
                type: input.type,
                location: input.location,
                required: input.required,
                description: input.description,
                example: input.example,
                apiCallID: apiCallID
            )
        }
        
        try await params.create(on: req.db)
        return .noContent
    }
    
    func updateParameter(req: Request) async throws -> HTTPStatus {
        guard
            let apiParamID = req.parameters.get("parameterID", as: UUID.self)
        else {
            throw Abort(.badRequest)
        }
        
        let input = try req.content.decode(UpdateParameterDTO.self)
        guard let parameter = try await ParameterModel.find(apiParamID, on: req.db)
        else {
            throw Abort(.notFound, reason: "parameter not found")
        }
        parameter.name = input.name ?? parameter.name
        parameter.type = input.type ?? parameter.type
        parameter.location = input.location ?? parameter.location
        parameter.required = input.required ?? parameter.required
        parameter.description = input.description ?? parameter.description
        parameter.example = input.type ?? parameter.example
        
        try await parameter.save(on: req.db)
        return .noContent
    }
    
    func deleteParameter(req: Request) async throws -> HTTPStatus {
        guard
            let apiParamID = req.parameters.get("parameterID", as: UUID.self)
        else {
            throw Abort(.badRequest)
        }
        
        guard let parameter = try await ParameterModel.find(apiParamID, on: req.db)
        else {
            throw Abort(.notFound, reason: "parameter not found")
        }
        try await parameter.delete(on: req.db)
        return .noContent
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
            .with(\.$schemas)
            .all()
    }
    
    func linkSchemaWithResponse(req: Request) async throws -> APIResponseModel {
        let input = try req.content.decode(LinkResponseSchemaDTO.self)
        guard let schema = try await SchemaModel.query(on: req.db).filter(\.$id == input.schemaID).first()
        else {
            throw Abort(.notFound, reason: "schema not found")
        }
        
        guard let response = try await APIResponseModel.query(on: req.db).filter(\.$id == input.responseID).first()
        else {
            throw Abort(.notFound, reason: "response not found")
        }
        try await schema.$apiResponses.attach(response, on: req.db)
        try await schema.save(on: req.db)
        
        try await response.$schemas.load(on: req.db)
        return response
    }
    
    func linkSchemaRequestWithAPI(req: Request) async throws -> APICallModel {
        let input = try req.content.decode(LinkAPISchemaDTO.self)
        guard let schema = try await SchemaModel.query(on: req.db).filter(\.$id == input.schemaID).first()
        else {
            throw Abort(.notFound, reason: "schema not found")
        }
        
        guard let apiCall = try await APICallModel.query(on: req.db).filter(\.$id == input.apiCallId).first()
        else {
            throw Abort(.notFound, reason: "response not found")
        }
        schema.$apiCall.id = input.apiCallId
        try await schema.save(on: req.db)
        try await apiCall.$requestModel.load(on: req.db)
        return apiCall
    }
}
