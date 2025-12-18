// OpenAPIImportController.swift
import Vapor
import Yams
import Fluent

struct ImportOpenAPIRequest: Content {
    let url: String
}


struct OpenAPIImportController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let importRoutes = routes.grouped("api", "v1", "import")
        importRoutes.post("openapi", use: importOpenAPI)
    }
    
    // Основная функция импорта
    func importOpenAPI(req: Request) async throws -> ImportStats {
        let input = try req.content.decode(ImportOpenAPIRequest.self)
        
        // Загружаем OpenAPI спецификацию
        return try await loadOpenAPIDocument(from: input.url, req: req)
    }
    
    // MARK: - Вспомогательные методы
    
    private func loadOpenAPIDocument(from urlString: String, req: Request) async throws -> ImportStats  {
        guard let url = URL(string: urlString) else {
            throw Abort(.badRequest, reason: "Некорректный URL")
        }
        let decoder = JSONDecoder()
        
        // Загружаем содержимое спецификации
        let response: ClientResponse
        if url.scheme == "file" || url.isFileURL {
            // Локальный файл
            let filePath = url.absoluteString.replacingOccurrences(of: "file://", with: "")
            guard FileManager.default.fileExists(atPath: filePath) else {
                throw Abort(.badRequest, reason: "Файл не найден")
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let body = ByteBuffer(data: data)
            response = ClientResponse(status: .ok, body: body)
        } else {
            // Удаленный URL
            response = try await req.client.get(URI(string: url.absoluteString))
        }
        
        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Не удалось загрузить файл. Статус: \(response.status)")
        }
        
        guard let body = response.body else {
            throw Abort(.badRequest, reason: "Пустой ответ")
        }
        
        var stats = ImportStats()
        let data = Data(buffer: body)
        
        let spec = try OpenAPIDecoder.decode(from: data)
        let service = try await handleService(spec: spec, on: req.db, stats: &stats)
        
        try await DatabaseSchemaImporter.importAllSchemasToDatabase(
            from: spec,
            serviceID: service.requireID(),
            on: req.db
        )
        try await handleApiCalls(spec, for: service, on: req.db, stats: &stats)
        print("✅ Successfully imported api")
        return stats
    }
    
    func handleService(spec: OpenAPISpec, on db: Database, stats: inout ImportStats) async throws  -> ServiceModel {
        let serviceInfo = spec.info
        let service = ServiceModel(name: spec.info.title, version: spec.info.version, type: "internal", owner: "TODO: Check owner")
        try await service.save(on: db)
        print("✅ Successfully created service")
        return service
    }
    
    func handleApiCalls(_ spec: OpenAPISpec, for service: ServiceModel, on db: Database, stats: inout ImportStats) async throws {
        let calls = spec.getSummary().paths
        for call in calls {
            let apiCall = APICallModel(
                path: call.path,
                method: call.method,
                description: call.summary ?? "TODO: Add description",
                serviceID: try service.requireID()
            )
            try await apiCall.save(on: db)
            stats.importedEndpoints += 1

            let params = call.operation.parameters?.filter {$0.in == .path || $0.in == .query } ?? []
            let parameterModels = try params.reduce(into: [ParameterModel]()) { partialResult, param in
                partialResult.append(
                    ParameterModel(
                        name: param.name,
                        type: param.schema?.type?.value ?? "string",
                        location: param.in.rawValue,
                        required: param.required ?? false,
                        description: param.description,
                        apiCallID: try apiCall.requireID()
                    )
                )
            }
            try await parameterModels.create(on: db)
            stats.importedParameters += parameterModels.count
            
            // requestBody
            let sdt = SchemaModelProcessor.extractRequestBodySchemas(from: call, with: spec)
            
            if let requestDataModel = sdt.0 {
                if let model = try await SchemaModel
                    .query(on: db)
                    .filter(\.$name == requestDataModel)
                    .first() {
                    try await model.$apiCalls.attach(apiCall, on: db) { pivot in
                        pivot.type = sdt.1
                    }
                    try await model.save(on: db)
                    stats.linkedSchemas += 1
                }
            }
            
            // responses
            
            
            for response in call.responses {
                let responseModel = APIResponseModel(
                    statusCode: Int(response.statusCode) ?? 999,
                    contentType: response.contentTypes?.first ?? "application/json",
                    apiCallID: try apiCall.requireID()
                )
                try await responseModel.save(on: db)
                stats.importedResponses += 1
                let sdt = SchemaModelProcessor.extractResponseBodySchemas(
                    from: response,
                    and: call
                )
                if let responseDataModel = sdt.0 {
                    if let responseSchema = try await SchemaModel.query(on: db)
                        .filter(\.$name == responseDataModel )
                        .first() {
                        try await responseSchema.$apiResponses.attach(responseModel, on: db) { pivot in
                            pivot.type = sdt.1
                        }
                        try await responseSchema.save(on: db)
                        stats.linkedSchemas += 1
                    }
                }
            }
        }
    }
}
    
struct ImportStats: Content {
    var importedEndpoints: Int = 0
    var linkedSchemas: Int = 0
    var importedParameters: Int = 0
    var importedResponses: Int = 0
}

class SchemaModelProcessor {
    // MARK: - Основные методы
    
    /// Извлекает все requestBody из спецификации и преобразует их в данные для SchemaModel
    static func extractRequestBodySchemas(from endpoint: EndpointInfo, with spec: OpenAPISpec) -> (String?, String?) {
        
        // Проверяем, есть ли requestBody в операции
        guard let requestBody = endpoint.operation.requestBody,
              let jsonContent = requestBody.content["application/json"],
              let schema = jsonContent.schema else {
            return (nil, nil)
        }
        
        // Генерируем имя для схемы
        let schemaName: String
        var schemaType: String?
        if let ref = schema.ref {
            schemaName = extractSchemaName(from: ref)
        } else if let ref = schema.items?.ref {
            schemaName = extractSchemaName(from: ref)
            schemaType = "Items"
        } else {
            schemaName = generateSchemaName(
                from: endpoint.operation.operationId ?? "",
                path: endpoint.path,
                method: endpoint.method
            )
        }
        
        return (schemaName, schemaType)
    }
    
    /// Извлекает все responseBody из спецификации
    static func extractResponseBodySchemas(from response: ResponseInfo, and endpoint: EndpointInfo) -> (String?, String?) {
        
        guard
            let content = response.response.content?["application/json"],
            let schema = content.schema else {
            return (nil, nil)
        }
        
        let schemaName: String
        var schemaType: String?
        if let ref = schema.ref {
            schemaName = extractSchemaName(from: ref)
        } else if let ref = schema.items?.ref {
            schemaName = extractSchemaName(from: ref)
            schemaType = "Items"
        } else {
            // Генерируем имя для схемы
            schemaName = generateSchemaName(
                from: endpoint.operation.operationId ?? "",
                path: endpoint.path,
                method: endpoint.method,
                isResponse: true,
                statusCode: response.statusCode
            )
        }
        return (schemaName, schemaType)
    }
    
    // MARK: - Вспомогательные методы
    
    private static func extractSchemaName(from ref: String) -> String {
        let components = ref.components(separatedBy: "/")
        return components.last ?? ref
    }
    
    private static func generateSchemaName(
        from operationId: String,
        path: String,
        method: String,
        isResponse: Bool = false,
        statusCode: String? = nil
    ) -> String {
        let cleanedOperationId = operationId
            .replacingOccurrences(of: "_api_v1_", with: "")
            .replacingOccurrences(of: "_api_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .replacingOccurrences(of: " ", with: "")
        
        let suffix = isResponse ? "Response" : "Request"
        let statusSuffix = statusCode.map { "\($0)" } ?? ""
        
        return "\(cleanedOperationId)\(statusSuffix)\(suffix)"
    }
}

