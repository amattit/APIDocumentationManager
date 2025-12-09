// OpenAPIImportController.swift
import Vapor
import OpenAPIKit
import Yams

struct OpenAPIImportController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let importRoutes = routes.grouped("api", "v1", "import")
        importRoutes.post("openapi", use: importOpenAPI)
    }
    
    // Основная функция импорта
    func importOpenAPI(req: Request) async throws -> ImportResultDTO {
        let input = try req.content.decode(ImportOpenAPIRequest.self)
        
        // Загружаем OpenAPI спецификацию
        let document: OpenAPI.Document
        do {
            document = try await loadOpenAPIDocument(from: input.url, req: req)
        } catch {
            throw Abort(.badRequest, reason: "Не удалось загрузить OpenAPI спецификацию: \(error)")
        }
        
        // Извлекаем информацию о сервисе
        let serviceInfo = extractServiceInfo(from: document.info)
        
        // Создаем или обновляем сервис
        let service = try await createOrUpdateService(
            info: serviceInfo,
            on: req
        )
        
        var importStats = ImportStats()
        
        // Импортируем схемы из components
        let schemaMap = try await importSchemas(
            from: document.components.schemas,
            on: req
        )
        
        // Импортируем API вызовы
        for (path, pathItem) in document.paths {
            try await importPath(
                path: path.rawValue,
                pathItem: pathItem.pathItemValue!,
                service: service,
                components: document.components,
                schemaMap: schemaMap,
                on: req,
                stats: &importStats
            )
        }
        
        return ImportResultDTO(
            serviceName: service.name,
            serviceVersion: service.version,
            importedEndpoints: importStats.importedEndpoints,
            importedSchemas: importStats.importedSchemas,
            importedParameters: importStats.importedParameters,
            importedResponses: importStats.importedResponses
        )
    }
    
    // MARK: - Вспомогательные методы
    
    private func loadOpenAPIDocument(from urlString: String, req: Request) async throws -> OpenAPI.Document {
        guard let url = URL(string: urlString) else {
            throw Abort(.badRequest, reason: "Некорректный URL")
        }
        
        // Загружаем содержимое спецификации
        let response = try await req.client.get(URI(string: url.absoluteString))
        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Не удалось загрузить файл")
        }
        
        guard let body = response.body else {
            throw Abort(.badRequest, reason: "Пустой ответ")
        }
        
        let data = Data(buffer: body)
        
        // Определяем формат (JSON или YAML)
        let isJSON = url.pathExtension.lowercased() == "json" ||
                     (data.first == 0x7B) // Проверяем первый байт на '{' для JSON
        
        if isJSON {
            return try JSONDecoder().decode(OpenAPI.Document.self, from: data)
        } else {
            let yamlString = String(data: data, encoding: .utf8) ?? ""
            return try YAMLDecoder().decode(OpenAPI.Document.self, from: yamlString)
        }
    }
    
    private func extractServiceInfo(from info: OpenAPI.Document.Info) -> ServiceInfo {
        return ServiceInfo(
            name: info.title,
            version: info.version,
            description: info.description,
            owner: info.contact?.name ?? "unknown"
        )
    }
    
    private func createOrUpdateService(info: ServiceInfo, on req: Request) async throws -> ServiceModel {
        // Проверяем существование сервиса
        if let existingService = try await ServiceModel.query(on: req.db)
            .filter(\.$name, .equal, info.name)
            .filter(\.$version, .equal, info.version)
            .first() {
            // Обновляем существующий сервис
            existingService.description = info.description
            try await existingService.save(on: req.db)
            return existingService
        } else {
            // Создаем новый сервис
            let service = ServiceModel(
                name: info.name,
                version: info.version,
                type: "external",
                owner: info.owner,
                description: info.description
            )
            try await service.save(on: req.db)
            return service
        }
    }
    
    private func importSchemas(
        from schemas: OpenAPI.ComponentDictionary<JSONSchema>,
        on req: Request
    ) async throws -> [String: SchemaModel] {
        var schemaMap: [String: SchemaModel] = [:]
        
        for (schemaName, schema) in schemas {
            let schemaModel = try await importSchema(
                name: schemaName.rawValue,
                schema: schema,
                on: req
            )
            schemaMap[schemaName.rawValue] = schemaModel
        }
        
        return schemaMap
    }
    
    private func importSchema(
        name: String,
        schema: JSONSchema,
        on req: Request
    ) async throws -> SchemaModel {
        // Создаем схему
        let schemaModel = SchemaModel(name: name)
        try await schemaModel.save(on: req.db)
        
        // Рекурсивно импортируем атрибуты
        try await importSchemaAttributes(
            from: schema,
            parentPath: [],
            parentSchema: schemaModel,
            on: req
        )
        
        return schemaModel
    }
    
    private func importSchemaAttributes(
        from schema: JSONSchema,
        parentPath: [String],
        parentSchema: SchemaModel,
        on req: Request
    ) async throws {
        switch schema.value {
        case .object(let format, let context):
            // Обрабатываем свойства объекта
            for (propertyName, propertySchema) in context.properties {
                let currentPath = parentPath + [propertyName]
                
                // Создаем атрибут для свойства
                let attribute = try await createAttribute(
                    name: propertyName,
                    schema: propertySchema,
                    path: currentPath,
                    parentSchema: parentSchema,
                    on: req
                )
                
                // Рекурсивно обрабатываем вложенные объекты
                if case .object = propertySchema.value {
                    try await importSchemaAttributes(
                        from: propertySchema,
                        parentPath: currentPath,
                        parentSchema: parentSchema,
                        on: req
                    )
                }
                
                // Обрабатываем массивы объектов
                if case .array(_, let arrayContext) = propertySchema.value {
                    if let items = arrayContext.items,
                       case .object = items.value {
                        try await importSchemaAttributes(
                            from: items,
                            parentPath: currentPath + ["[]"],
                            parentSchema: parentSchema,
                            on: req
                        )
                    }
                }
            }
            
        case .array(_, let context):
            // Обрабатываем элементы массива
            if let items = context.items,
               case .object = items.value {
                try await importSchemaAttributes(
                    from: items,
                    parentPath: parentPath + ["[]"],
                    parentSchema: parentSchema,
                    on: req
                )
            }
            
        default:
            // Примитивные типы не требуют рекурсивной обработки
            break
        }
    }
    
    private func createAttribute(
        name: String,
        schema: JSONSchema,
        path: [String],
        parentSchema: SchemaModel,
        on req: Request
    ) async throws -> SchemaAttributeModel {
        let type = getSchemaType(from: schema)
        let isNullable = schema.nullable
        
        let attribute = SchemaAttributeModel(
            name: path.joined(separator: "."),
            type: type,
            isNullable: isNullable,
            description: schema.description ?? "",
            defaultValue: getDefaultValue(from: schema),
            schemaID: parentSchema.id!
        )
        
        try await attribute.save(on: req.db)
        return attribute
    }
    
    private func getSchemaType(from schema: JSONSchema) -> String {
        switch schema.value {
        case .string(let context, _):
            let format = context.format.rawValue
            return "string(\(format))"
        case .integer(let context, _):
            let format = context.format.rawValue
            return "integer(\(format))"
        case .number(let context, _):
            let format = context.format.rawValue
            return "number(\(format))"
        case .boolean:
            return "boolean"
        case .object:
            return "object"
        case .array:
            return "array"
        case .reference(let ref, _):
            return "ref(\(ref.name ?? ""))"
        case .all, .one, .any:
            return "composite"
        case .not:
            return "not"
        case .fragment:
            return "any"
        case .null(_):
            return "null"
        }
    }
    
    private func getSchemaType(from schema: OpenAPI.Parameter.SchemaContext) -> String {
        switch schema.schema {
        case .a(let jsonSchema):
            return "null"
        case .b(let jsonSchema):
            return getSchemaType(from: jsonSchema)
        }
    }
    
    private func getDefaultValue(from schema: JSONSchema) -> String? {
        switch schema.value {
        case .string(let context, _):
            if let defaultValue = context.defaultValue {
                return "\(defaultValue)"
            }
            return nil
        case .integer(let context, _):
            if let defaultValue = context.defaultValue {
                return "\(defaultValue)"
            }
            return nil
        case .number(let context, _):
            if let defaultValue = context.defaultValue {
                return "\(defaultValue)"
            }
            return nil
        case .boolean(let context):
            if let defaultValue = context.defaultValue {
                return "\(defaultValue)"
            }
            return nil
        default:
            return nil
        }
    }
    
    private func importPath(
        path: String,
        pathItem: OpenAPI.PathItem,
        service: ServiceModel,
        components: OpenAPI.Components?,
        schemaMap: [String: SchemaModel],
        on req: Request,
        stats: inout ImportStats
    ) async throws {
        // Импортируем операции для каждого метода
        for metoper in pathItem.endpoints {
            // Создаем API вызов
            let apiCall = APICallModel(
                path: path,
                method: metoper.method.rawValue.uppercased(),
                description: metoper.operation.description ?? metoper.operation.summary ?? "No description",
                tags: metoper.operation.tags?.map { $0 } ?? [],
                serviceID: service.id!
            )
            try await apiCall.save(on: req.db)
            stats.importedEndpoints += 1
            
            // Импортируем параметры
            let allParameters = metoper.operation.parameters + pathItem.parameters
            for parameter in allParameters {
                try await importParameter(
                    parameter: parameter.b!,
                    apiCall: apiCall,
                    components: components,
                    on: req,
                    stats: &stats
                )
            }
            
            // Импортируем тело запроса
            if let requestBody = metoper.operation.requestBody {
                try await importRequestBody(
                    requestBody: requestBody.b!,
                    apiCall: apiCall,
                    components: components,
                    schemaMap: schemaMap,
                    on: req
                )
            }
            
            // Импортируем ответы
            for (statusCode, response) in metoper.operation.responses {
                try await importResponse(
                    statusCode: statusCode,
                    response: response.b!,
                    apiCall: apiCall,
                    components: components,
                    schemaMap: schemaMap,
                    on: req,
                    stats: &stats
                )
            }
        }
    }
    
    private func importParameter(
        parameter: OpenAPI.Parameter,
        apiCall: APICallModel,
        components: OpenAPI.Components?,
        on req: Request,
        stats: inout ImportStats
    ) async throws {
        let paramType: String
        let example: String?
        
        switch parameter.schemaOrContent {
        case .a(let schema):
            paramType = getSchemaType(from: schema)
            example = getExample(from: schema)
        case .b:
            paramType = "content"
            example = nil
        }
        
        let param = ParameterModel(
            name: parameter.name,
            type: paramType,
            location: parameter.location.rawValue,
            required: parameter.required,
            description: parameter.description,
            example: example,
            apiCallID: apiCall.id!
        )
        
        try await param.save(on: req.db)
        stats.importedParameters += 1
    }
    
    private func getExample(from schema: OpenAPI.Parameter.SchemaContext) -> String? {
        if let example = schema.examples?.first {
            switch example.value {
            case .a(let a):
                return a.name
            case .b(let b):
                return b.description
            }
        }
        return ""
    }
    
    private func importRequestBody(
        requestBody: OpenAPI.Request,
        apiCall: APICallModel,
        components: OpenAPI.Components?,
        schemaMap: [String: SchemaModel],
        on req: Request
    ) async throws {
        // Получаем схему из тела запроса
        guard let content = requestBody.content.first else { return }
        if let schema = content.value.schema {
            // Находим или создаем схему
            let schemaModel: SchemaModel
            
            if case .b(let ref) = schema,
               let existingSchema = schemaMap[ref.title ?? "string"] {
                schemaModel = existingSchema
            } else {
                // Создаем новую схему для запроса
                schemaModel = try await importSchema(
                    name: "\(apiCall.path.replacingOccurrences(of: "/", with: "_"))_\(apiCall.method)_request",
                    schema: schema.b!,
                    on: req
                )
            }
            
            // Связываем схему с API вызовом
            let linkDTO = LinkAPISchemaDTO(
                apiCallId: apiCall.id!,
                schemaID: schemaModel.id!
            )
            
            let request = Request(
                application: req.application,
                method: .POST,
                url: URI(string: "/api/v1/calls/link-schema-request"),
                headers: req.headers,
                collectedBody: ByteBufferAllocator().buffer(data: try JSONEncoder().encode(linkDTO)),
                remoteAddress: req.remoteAddress,
                on: req.eventLoop
            )
            
            _ = try await APICallController().linkSchemaRequestWithAPI(req: request)
        }
    }
    
    private func importResponse(
        statusCode: OpenAPI.Response.StatusCode,
        response: OpenAPI.Response,
        apiCall: APICallModel,
        components: OpenAPI.Components?,
        schemaMap: [String: SchemaModel],
        on req: Request,
        stats: inout ImportStats
    ) async throws {
        let statusCodeValue = 200
        
        // Получаем контент из ответа
        let content = response.content.first?.value
        let contentType = response.content.first?.key.rawValue ?? "application/json"
        
        // Создаем DTO для ответа
        let responseDTO = CreateResponseDTO(
            statusCode: statusCodeValue,
            description: response.description,
            contentType: contentType,
            examples: extractExamples(from: content),
            headers: nil
        )
        
        // Создаем ответ через существующий контроллер
        let request = Request(
            application: req.application,
            method: .POST,
            url: URI(string: "/api/v1/calls/\(apiCall.id!)/responses"),
            headers: req.headers,
            collectedBody: ByteBufferAllocator().buffer(data:try JSONEncoder().encode(responseDTO)),
            remoteAddress: req.remoteAddress,
            on: req.eventLoop
        )
        
        let createdResponse = try await APICallController().createResponse(req: request)
        stats.importedResponses += 1
        
        // Связываем схему с ответом, если есть
        if let schema = content?.schema {
            let schemaModel: SchemaModel
            
            if case .b(let ref) = schema,
               let existingSchema = schemaMap[ref.title ?? "string"] {
                schemaModel = existingSchema
            } else {
                // Создаем новую схему для ответа
                schemaModel = try await importSchema(
                    name: "\(apiCall.path.replacingOccurrences(of: "/", with: "_"))_\(apiCall.method)_response_\(statusCodeValue)",
                    schema: schema.b!,
                    on: req
                )
                stats.importedSchemas += 1
            }
            
            // Связываем схему с ответом
            let linkDTO = LinkResponseSchemaDTO(
                responseID: createdResponse.id!,
                schemaID: schemaModel.id!
            )
            
            let linkRequest = Request(
                application: req.application,
                method: .POST,
                url: URI(string: "/api/v1/calls/link-schema-response"),
                headers: req.headers,
                collectedBody: ByteBufferAllocator().buffer(data:try JSONEncoder().encode(linkDTO)),
                remoteAddress: req.remoteAddress,
                on: req.eventLoop
            )
            
            _ = try await APICallController().linkSchemaWithResponse(req: linkRequest)
        }
    }
    
    private func extractExamples(from content: OpenAPI.Content?) -> [String: String]? {
        guard let examples = content?.examples else { return nil }
        
        var result: [String: String] = [:]
        for (key, example) in examples {
            switch example {
            
            case .a(let value):
                if let valueString = try? String(data: JSONEncoder().encode(value), encoding: .utf8) {
                    result[key] = valueString
                }
            case .b:
                continue
            }
        }
        
        return result.isEmpty ? nil : result
    }
}

// MARK: - DTO для импорта

struct ImportOpenAPIRequest: Content {
    let url: String
}

struct ImportResultDTO: Content {
    let serviceName: String
    let serviceVersion: String
    let importedEndpoints: Int
    let importedSchemas: Int
    let importedParameters: Int
    let importedResponses: Int
}

// MARK: - Вспомогательные структуры

struct ServiceInfo {
    let name: String
    let version: String
    let description: String?
    let owner: String
}

struct ImportStats {
    var importedEndpoints: Int = 0
    var importedSchemas: Int = 0
    var importedParameters: Int = 0
    var importedResponses: Int = 0
}

// MARK: - Регистрация контроллера

extension OpenAPIImportController {
    static func registerRoutes(_ app: Application) throws {
        try app.routes.register(collection: OpenAPIImportController())
    }
}
