//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Vapor
import Fluent

public struct ServiceController: RouteCollection {
    private let openAPIParser: OpenAPIParserProtocol
    private let openAPIExporter: OpenAPIExporterProtocol
    
    public init(openAPIParser: OpenAPIParserProtocol = OpenAPIParser(),
                openAPIExporter: OpenAPIExporterProtocol) {
        self.openAPIParser = openAPIParser
        self.openAPIExporter = openAPIExporter
    }
    
    public func boot(routes: RoutesBuilder) throws {
        let services = routes.grouped("api", "v1", "services")
        
        // CRUD операций для сервисов
        services.get(use: getAllServices)
        services.post(use: createService)
        
        // Импорт/экспорт OpenAPI
        services.post("import", "openapi", use: importOpenAPIWithSchemas)
        services.get("export", "openapi", use: exportOpenAPI)
        
        services.group(":serviceId") { service in
            service.get(use: getService)
            service.put(use: updateService)
            service.delete(use: deleteService)
            
            // API endpoints
            service.get("endpoints", use: getServiceEndpoints)
            service.post("endpoints", use: createEndpoint)
            
            // Граф зависимостей
            service.get("dependency-graph", use: getDependencyGraph)
            service.get("terminal-endpoints", use: getTerminalEndpoints)
        }
        
        // Глобальные операции
        services.get("dependency-chain", use: findDependencyChain)
    }
    
    // MARK: - Service CRUD
    
    private func getAllServices(req: Request) async throws -> [Service] {
        return try await Service.query(on: req.db).all()
    }
    
    private func getService(req: Request) async throws -> Service {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        guard let service = try await Service.find(serviceId, on: req.db) else {
            throw Abort(.notFound, reason: "Service not found")
        }
        
        return service
    }
    
    private func createService(req: Request) async throws -> Service {
        let service = try req.content.decode(Service.self)
        try await service.save(on: req.db)
        return service
    }
    
    private func updateService(req: Request) async throws -> Service {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        guard let service = try await Service.find(serviceId, on: req.db) else {
            throw Abort(.notFound, reason: "Service not found")
        }
        
        let updatedService = try req.content.decode(Service.self)
        service.name = updatedService.name
        service.version = updatedService.version
        service.type = updatedService.type
        service.department = updatedService.department
        service.description = updatedService.description
        service.environments = updatedService.environments
        service.owner = updatedService.owner
        service.contactEmail = updatedService.contactEmail
        
        try await service.save(on: req.db)
        return service
    }
    
    private func deleteService(req: Request) async throws -> HTTPStatus {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        guard let service = try await Service.find(serviceId, on: req.db) else {
            throw Abort(.notFound, reason: "Service not found")
        }
        
        try await service.delete(on: req.db)
        return .noContent
    }
    
    // MARK: - OpenAPI Import/Export
    struct ImportRequest: Content {
        let fileURL: String
        let format: OpenAPIFormat
    }
    
    struct ImportResponse: Content {
        let service: Service
        let endpoints: [APIEndpoint]
        let importedCount: Int
    }
    
//    private func importOpenAPI(req: Request) async throws -> ImportResponse {
//        
//        
//        let importRequest = try req.content.decode(ImportRequest.self)
//        let fileURL = URL(string: importRequest.fileURL)!
//        
//        let (service, endpoints) = try openAPIParser.parse(from: fileURL)
//        
//        // Сохраняем сервис
//        try await service.save(on: req.db)
//        
//        // Сохраняем endpoints
//        for endpoint in endpoints {
//            endpoint.$service.id = service.id!
//            try await endpoint.save(on: req.db)
//        }
//        
//        return ImportResponse(
//            service: service,
//            endpoints: endpoints,
//            importedCount: endpoints.count
//        )
    //    }
    
    private func exportOpenAPI(req: Request) async throws -> Response {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        guard let service = try await Service.find(serviceId, on: req.db) else {
            throw Abort(.notFound, reason: "Service not found")
        }
        
        let endpoints = try await APIEndpoint.query(on: req.db)
            .filter(\.$service.$id, .equal, serviceId)
            .all()
        
        let format = req.query["format"] == "yaml" ? OpenAPIFormat.yaml : .json
        
        let exporter = OpenAPIExporter(database: req.db)
        let fileURL = try await exporter.generateOpenAPIFile(
            service: service,
            endpoints: endpoints,
            format: format
        )
        
        return req.fileio.streamFile(at: fileURL.path)
    }
    
    // MARK: - Endpoints Management
    
    private func getServiceEndpoints(req: Request) async throws -> [APIEndpoint] {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        return try await APIEndpoint.query(on: req.db)
            .filter(\.$service.$id, .equal, serviceId)
            .all()
    }
    
    private func createEndpoint(req: Request) async throws -> APIEndpoint {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        let endpoint = try req.content.decode(APIEndpoint.self)
        endpoint.$service.id = serviceId
        try await endpoint.save(on: req.db)
        return endpoint
    }
    
    // MARK: - Dependency Graph
    
    private func getDependencyGraph(req: Request) async throws -> DependencyGraph {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        guard let service = try await Service.find(serviceId, on: req.db) else {
            throw Abort(.notFound, reason: "Service not found")
        }
        
        let endpoints = try await APIEndpoint.query(on: req.db)
            .filter(\.$service.$id, .equal, serviceId)
            .all()
        
        let graphBuilder = DependencyGraphBuilder(database: req.db)
        return try await graphBuilder.buildGraph(for: service, endpoints: endpoints)
    }
    
    private func getTerminalEndpoints(req: Request) async throws -> [APIEndpoint] {
        guard let serviceId = req.parameters.get("serviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid service ID")
        }
        
        guard let service = try await Service.find(serviceId, on: req.db) else {
            throw Abort(.notFound, reason: "Service not found")
        }
        
        let graphBuilder = DependencyGraphBuilder(database: req.db)
        return try await graphBuilder.findTerminalEndpoints(for: service)
    }
    
    private func findDependencyChain(req: Request) async throws -> [ServiceDependency] {
        struct ChainRequest: Content {
            let fromServiceId: UUID
            let toServiceId: UUID
        }
        
        let chainRequest = try req.content.decode(ChainRequest.self)
        let graphBuilder = DependencyGraphBuilder(database: req.db)
        
        return try await graphBuilder.findDependencyChain(
            from: chainRequest.fromServiceId,
            to: chainRequest.toServiceId
        )
    }
}

struct ImportRequest: Content {
    let fileURL: String
}

struct ImportWithSchemasResponse: Content {
    let service: Service
    let endpoints: [APIEndpoint]
    let dataModels: [DataModel]
    let importedEndpointsCount: Int
    let importedModelsCount: Int
}

extension ServiceController {
    private func importOpenAPIWithSchemas(req: Request) async throws -> ImportWithSchemasResponse {
        
        
        let importRequest = try req.content.decode(ImportRequest.self)
        let fileURL = URL(string: importRequest.fileURL)!
        
        let data = try Data(contentsOf: fileURL)
        let format: OpenAPIFormat = fileURL.pathExtension.lowercased() == "json" ? .json : .yaml
        
        let parser = OpenAPIParser()
        let (service, endpoints, dataModels) = try parser.parseWithSchemas(from: data, format: format)
        
        // Сохраняем сервис
        try await service.save(on: req.db)
        
        // Обновляем ID моделей в endpoints (чтобы ссылки были корректными)
        let modelDictionary = Dictionary(uniqueKeysWithValues: dataModels.map { ($0.name, $0.id) })
        
        // Сохраняем endpoints с обновленными ссылками на модели
        var savedEndpoints: [APIEndpoint] = []
        for endpoint in endpoints {
            endpoint.$service.id = service.id!
            
            // Обновляем ссылки на модели
            if let requestBodySchemaRef = endpoint.requestBodySchemaRef {
                let modelName = extractModelName(from: requestBodySchemaRef)
                endpoint.$requestBodyModel.id = modelDictionary[modelName] as? UUID
            }
            
            // Обновляем параметры
            var updatedParameters: [APIParameter] = []
            for param in endpoint.parameters {
                if let schemaRef = param.schemaRef {
                    let modelName = extractModelName(from: schemaRef)
                    var updatedParam = param
                    updatedParam.dataModelId = modelDictionary[modelName] as? UUID
                    updatedParameters.append(updatedParam)
                } else {
                    updatedParameters.append(param)
                }
            }
            endpoint.parameters = updatedParameters
            
            // Обновляем ответы
            var updatedResponses: [APIResponse] = []
            for response in endpoint.responses {
                if let schemaRef = response.schemaRef {
                    let modelName = extractModelName(from: schemaRef)
                    var updatedResponse = response
                    updatedResponse.dataModelId = modelDictionary[modelName] as? UUID
                    updatedResponses.append(updatedResponse)
                } else {
                    updatedResponses.append(response)
                }
            }
            endpoint.responses = updatedResponses
            
            try await endpoint.save(on: req.db)
            savedEndpoints.append(endpoint)
        }
        
        // Сохраняем модели данных
        for model in dataModels {
            model.$service.id = service.id!
            
            let endpoint = endpoints.first { point in
                point.responseModels.contains { cmodel in
                    cmodel.id == model.id
                }
            }
            model.$endpoint.id = try endpoint!.requireID()
            try await model.save(on: req.db)
        }
        
        return ImportWithSchemasResponse(
            service: service,
            endpoints: savedEndpoints,
            dataModels: dataModels,
            importedEndpointsCount: savedEndpoints.count,
            importedModelsCount: dataModels.count
        )
    }
    
    private func extractModelName(from ref: String) -> String {
        return ref.components(separatedBy: "/").last ?? ref
    }
}
