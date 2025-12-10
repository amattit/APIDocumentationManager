// OpenAPIImportController.swift
import Vapor
import OpenAPIKit
import Yams
import Fluent

struct OpenAPIImportController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let importRoutes = routes.grouped("api", "v1", "import")
        importRoutes.post("openapi", use: importOpenAPI)
    }
    
    // Основная функция импорта
    func importOpenAPI(req: Request) async throws -> /*ImportResultDTO*/HTTPStatus {
        let input = try req.content.decode(ImportOpenAPIRequest.self)
        
        // Загружаем OpenAPI спецификацию
        let document = try await loadOpenAPIDocument(from: input.url, req: req)
        
        print(document.warnings)
        return .ok
    }
    
    // MARK: - Вспомогательные методы
    
    private func loadOpenAPIDocument(from urlString: String, req: Request) async throws -> OpenAPI.Document {
        guard let url = URL(string: urlString) else {
            throw Abort(.badRequest, reason: "Некорректный URL")
        }
        
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
        
        let data = Data(buffer: body)
        
        // Определяем формат (JSON или YAML)
        if let contentType = response.headers.first(name: "Content-Type") {
            if contentType.contains("json") {
                return try JSONDecoder().decode(OpenAPI.Document.self, from: data)
            } else if contentType.contains("yaml") || contentType.contains("yml") {
                let yamlString = String(data: data, encoding: .utf8) ?? ""
                return try YAMLDecoder().decode(OpenAPI.Document.self, from: yamlString)
            }
        }
        
        // Определяем по расширению или содержимому
        let isJSON = url.pathExtension.lowercased() == "json" ||
                     data.first == 0x7B || // '{' для JSON
                     data.first == 0x5B     // '[' для JSON массива
        
        if isJSON {
            return try JSONDecoder().decode(OpenAPI.Document.self, from: data)
        } else {
            guard let yamlString = String(data: data, encoding: .utf8) else {
                throw Abort(.badRequest, reason: "Невозможно декодировать содержимое как текст")
            }
            return try YAMLDecoder().decode(OpenAPI.Document.self, from: yamlString)
        }
    }
    
//    private func extractServiceInfo(from info: OpenAPI.Document.Info) -> ServiceInfo {
//        return ServiceInfo(
//            name: info.title,
//            version: info.version,
//            description: info.description,
//            owner: info.contact?.name ?? "unknown"
//        )
//    }
//    
//    private func createOrUpdateService(info: ServiceInfo, on database: Database) async throws -> ServiceModel {
//        // Проверяем существование сервиса
//        if let existingService = try await ServiceModel.query(on: database)
//            .filter(\.$name, .equal, info.name)
//            .filter(\.$version, .equal, info.version)
//            .first() {
//            // Обновляем существующий сервис
//            existingService.description = info.description
//            existingService.owner = info.owner
//            try await existingService.update(on: database)
//            return existingService
//        } else {
//            // Создаем новый сервис
//            let service = ServiceModel(
//                name: info.name,
//                version: info.version,
//                type: "external",
//                owner: info.owner,
//                description: info.description
//            )
//            try await service.create(on: database)
//            return service
//        }
//    }
//    
//    private func importSchemas(
//        from schemas: OpenAPI.ComponentDictionary<JSONSchema>,
//        on database: Database
//    ) async throws -> [String: SchemaModel] {
//        var schemaMap: [String: SchemaModel] = [:]
//        
//        for (schemaName, schema) in schemas {
//            let schemaModel = try await importSchema(
//                name: schemaName.rawValue,
//                schema: schema,
//                on: database
//            )
//            schemaMap[schemaName.rawValue] = schemaModel
//        }
//        
//        return schemaMap
//    }
//    
//    private func importSchema(
//        name: String,
//        schema: JSONSchema,
//        on database: Database
//    ) async throws -> SchemaModel {
//        // Создаем схему
//        let schemaModel = SchemaModel(
//            name: name
//        )
//        try await schemaModel.create(on: database)
//        
//        // Импортируем атрибуты
//        try await importSchemaAttributes(
//            from: schema,
//            parentPath: [],
//            parentSchema: schemaModel,
//            on: database
//        )
//        
//        return schemaModel
//    }
//    
//    private func importSchemaAttributes(
//        from schema: JSONSchema,
//        parentPath: [String],
//        parentSchema: SchemaModel,
//        on database: Database
//    ) async throws {
//        switch schema.value {
//        case .object(_, let context):
//            // Обрабатываем свойства объекта
//            for (propertyName, propertySchema) in context.properties {
//                let currentPath = parentPath + [propertyName]
//                
//                // Создаем атрибут для свойства
//                _ = try await createAttribute(
//                    name: propertyName,
//                    schema: propertySchema,
//                    path: currentPath,
//                    parentSchema: parentSchema,
//                    on: database
//                )
//                
//                // Рекурсивно обрабатываем вложенные объекты
//                if case .object = propertySchema.value {
//                    try await importSchemaAttributes(
//                        from: propertySchema,
//                        parentPath: currentPath,
//                        parentSchema: parentSchema,
//                        on: database
//                    )
//                }
//                
//                // Обрабатываем массивы объектов
//                if case .array(_, let arrayContext) = propertySchema.value,
//                   let items = arrayContext.items,
//                   case .object = items.value {
//                    try await importSchemaAttributes(
//                        from: items,
//                        parentPath: currentPath + ["[]"],
//                        parentSchema: parentSchema,
//                        on: database
//                    )
//                }
//            }
//            
//        case .array(_, let context):
//            // Обрабатываем элементы массива
//            if let items = context.items,
//               case .object = items.value {
//                try await importSchemaAttributes(
//                    from: items,
//                    parentPath: parentPath + ["[]"],
//                    parentSchema: parentSchema,
//                    on: database
//                )
//            }
//            
//        default:
//            // Примитивные типы не требуют рекурсивной обработки
//            break
//        }
//    }
//    
//    private func createAttribute(
//        name: String,
//        schema: JSONSchema,
//        path: [String],
//        parentSchema: SchemaModel,
//        on database: Database
//    ) async throws -> SchemaAttributeModel {
//        let attribute = SchemaAttributeModel(
//            name: name,
//            type: getSchemaType(from: schema),
//            isNullable: schema.nullable,
//            description: schema.description ?? "",
//            defaultValue: getDefaultValue(from: schema),
//            schemaID: parentSchema.id!
//        )
//        
//        try await attribute.create(on: database)
//        return attribute
//    }
//    
//    private func getSchemaType(from schema: JSONSchema) -> String {
//        switch schema.value {
//        case .string(let context, _):
//            return context.format.rawValue
//        case .integer(let context, _):
//            return context.format.rawValue
//        case .number(let context, _):
//            return context.format.rawValue
//        case .boolean:
//            return "boolean"
//        case .object:
//            return "object"
//        case .array:
//            return "array"
//        case .reference(let ref):
//            return "ref(\(ref.0.name ?? ref.1.title ?? "unknown"))"
//        case .all:
//            return "allOf"
//        case .one:
//            return "oneOf"
//        case .any:
//            return "anyOf"
//        case .not:
//            return "not"
//        case .fragment:
//            return "any"
//        case .null:
//            return "null"
//        }
//    }
//    
//    private func getDefaultValue(from schema: JSONSchema) -> String? {
//        return nil
//    }
//    
//    private func importPath(
//        path: String,
//        pathItem: OpenAPI.PathItem,
//        service: ServiceModel,
//        components: OpenAPI.Components?,
//        schemaMap: [String: SchemaModel],
//        on database: Database,
//        stats: inout ImportStats
//    ) async throws {
//        // Импортируем операции для каждого метода
//        for endpoint in pathItem.endpoints {
//            // Создаем API вызов
//            let apiCall = APICallModel(
//                path: path,
//                method: endpoint.method.rawValue.uppercased(),
//                description: endpoint.operation.description ?? endpoint.operation.summary ?? "No description",
//                tags: endpoint.operation.tags?.map { $0 } ?? [],
//                serviceID: service.id!
//            )
//            try await apiCall.create(on: database)
//            stats.importedEndpoints += 1
//            
//            // Импортируем параметры
//            let allParameters = endpoint.operation.parameters
//            for parameter in allParameters {
//                try await importParameter(
//                    parameter: parameter.b!,
//                    apiCall: apiCall,
//                    on: database,
//                    stats: &stats
//                )
//            }
//            
//            // Импортируем тело запроса
//            if let requestBody = endpoint.operation.requestBody?.b {
//                try await importRequestBody(
//                    requestBody: requestBody,
//                    apiCall: apiCall,
//                    components: components,
//                    schemaMap: schemaMap,
//                    on: database
//                )
//            }
//            
//            // Импортируем ответы
//            for (statusCode, response) in endpoint.operation.responses {
//                guard let responseValue = response.b else { continue }
//                try await importResponse(
//                    statusCode: statusCode,
//                    response: responseValue,
//                    apiCall: apiCall,
//                    components: components,
//                    schemaMap: schemaMap,
//                    on: database,
//                    stats: &stats
//                )
//            }
//        }
//    }
//    
//    private func importParameter(
//        parameter: OpenAPI.Parameter,
//        apiCall: APICallModel,
//        on database: Database,
//        stats: inout ImportStats
//    ) async throws {
//        let paramType: String
//        let example: String?
//        
//        switch parameter.schemaOrContent {
//        case .a(let schema):
//            paramType = "content"
//            example = getExample(from: schema)
//        case .b:
//            paramType = "content"
//            example = nil
//        }
//        
//        let param = ParameterModel(
//            name: parameter.name,
//            type: paramType,
//            location: parameter.location.rawValue,
//            required: parameter.required,
//            description: parameter.description,
//            example: example,
//            apiCallID: apiCall.id!
//        )
//        
//        try await param.create(on: database)
//        stats.importedParameters += 1
//    }
//    
//    private func getExample(from schema: OpenAPI.Parameter.SchemaContext) -> String? {
//        guard let examples = schema.examples else { return nil }
//        
//        for example in examples {
//            switch example.value {
//            case .a(let exampleValue):
//                if let jsonData = try? JSONSerialization.data(withJSONObject: exampleValue),
//                   let jsonString = String(data: jsonData, encoding: .utf8) {
//                    return jsonString
//                }
//            case .b(let exampleObject):
//                return exampleObject.summary ?? exampleObject.description
//            }
//        }
//        
//        return nil
//    }
//    
//    private func importRequestBody(
//        requestBody: OpenAPI.Request,
//        apiCall: APICallModel,
//        components: OpenAPI.Components?,
//        schemaMap: [String: SchemaModel],
//        on database: Database
//    ) async throws {
//        // Получаем схему из тела запроса
//        guard let content = requestBody.content.first else { return }
//        
//        if let schema = content.value.schema {
//            // Находим или создаем схему
//            let schemaModel: SchemaModel
//            
//            if case .b(let ref) = schema,
//               let refName = ref.title,
//               let existingSchema = schemaMap[refName] {
//                schemaModel = existingSchema
//                schemaModel.$apiCall.id = apiCall.id
//                try await schemaModel.save(on: database)
//            } else {
//                // Создаем новую схему для запроса
//                let schemaName = "\(apiCall.path.replacingOccurrences(of: "/", with: "_"))_\(apiCall.method)_request"
//                schemaModel = try await importSchema(
//                    name: schemaName,
//                    schema: schema.b ?? .fragment(),
//                    on: database
//                )
//                schemaModel.$apiCall.id = apiCall.id
//                try await schemaModel.save(on: database)
//            }
//        }
//    }
//    
//    private func importResponse(
//        statusCode: OpenAPI.Response.StatusCode,
//        response: OpenAPI.Response,
//        apiCall: APICallModel,
//        components: OpenAPI.Components?,
//        schemaMap: [String: SchemaModel],
//        on database: Database,
//        stats: inout ImportStats
//    ) async throws {
//        let statusCodeValue: Int = 200
//        
//        // Получаем контент из ответа
//        let content = response.content.first
//        let contentType = content?.key.rawValue ?? "application/json"
//        
//        // Создаем ответ
//        let responseModel = APIResponseModel(
//            statusCode: statusCodeValue,
//            description: response.description,
//            contentType: contentType,
//            examples: extractExamples(from: content?.value),
//            apiCallID: apiCall.id!
//        )
//        try await responseModel.create(on: database)
//        stats.importedResponses += 1
//        
//        // Связываем схему с ответом, если есть
//        if let schema = content?.value.schema {
//            let schemaModel: SchemaModel
//            
//            if case .b(let ref) = schema,
//               let refName = ref.title,
//               let existingSchema = schemaMap[refName] {
//                schemaModel = existingSchema
//            } else {
//                // Создаем новую схему для ответа
//                let schemaName = "\(apiCall.path.replacingOccurrences(of: "/", with: "_"))_\(apiCall.method)_response_\(statusCodeValue)"
//                schemaModel = try await importSchema(
//                    name: schemaName,
//                    schema: schema.b ?? .fragment(),
//                    on: database
//                )
//                stats.importedSchemas += 1
//            }
//            
//            schemaModel.$response.id = apiCall.id
//            try await schemaModel.save(on: database)
//            // Связываем схему с ответом
////            let responseSchema = SchemaModel(
////                responseID: responseModel.id!,
////                schemaID: schemaModel.id!
////            )
////            try await responseSchema.create(on: database)
//        }
//    }
//    
//    private func extractExamples(from content: OpenAPI.Content?) -> [String: String]? {
//        guard let examples = content?.examples else { return nil }
//        
//        var result: [String: String] = [:]
//        for (key, example) in examples {
//            switch example {
//            case .a(let exampleValue):
//                if let jsonData = try? JSONSerialization.data(withJSONObject: exampleValue),
//                   let jsonString = String(data: jsonData, encoding: .utf8) {
//                    result[key] = jsonString
//                }
//            case .b(let exampleObject):
//                result[key] = exampleObject.summary ?? exampleObject.description ?? ""
//            }
//        }
//        
//        return result.isEmpty ? nil : result
//    }
}

// MARK: - DTO для импорта

struct ImportOpenAPIRequest: Content {
    let url: String
}

//struct ImportResultDTO: Content {
//    let serviceName: String
//    let serviceVersion: String
//    let importedEndpoints: Int
//    let importedSchemas: Int
//    let importedParameters: Int
//    let importedResponses: Int
//}

// MARK: - Вспомогательные структуры

//struct ServiceInfo {
//    let name: String
//    let version: String
//    let description: String?
//    let owner: String
//}

struct ImportStats {
    var importedEndpoints: Int = 0
    var importedSchemas: Int = 0
    var importedParameters: Int = 0
    var importedResponses: Int = 0
}

