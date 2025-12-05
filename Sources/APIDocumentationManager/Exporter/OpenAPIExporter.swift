//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Foundation
import Vapor
import Yams
import Fluent

public protocol OpenAPIExporterProtocol {
    func export(service: Service, endpoints: [APIEndpoint], format: OpenAPIFormat) async throws -> Data
    func generateOpenAPIFile(service: Service, endpoints: [APIEndpoint], format: OpenAPIFormat) async throws -> URL
}

public struct OpenAPIExporter: OpenAPIExporterProtocol {
    
    private let database: Database
    
    public init(database: Database) {
        self.database = database
    }
    
    public func export(service: Service, endpoints: [APIEndpoint], format: OpenAPIFormat) async throws -> Data {
        let openAPIDocument = try await createOpenAPIDocument(
            from: service,
            endpoints: endpoints
        )
        
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(openAPIDocument)
        case .yaml:
            let yamlString = try Yams.dump(object: openAPIDocument.toDictionary())
            return Data(yamlString.utf8)
        }
    }
    
    public func generateOpenAPIFile(service: Service, endpoints: [APIEndpoint], format: OpenAPIFormat) async throws -> URL {
        let data = try await export(service: service, endpoints: endpoints, format: format)
        let fileName = "\(service.name)_v\(service.version).\(format.rawValue)"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    private func createOpenAPIDocument(from service: Service, endpoints: [APIEndpoint]) async throws -> OpenAPIExportDocument {
        var paths: [String: OpenAPIExportPathItem] = [:]
        
        for endpoint in endpoints {
            var pathItem = paths[endpoint.path] ?? OpenAPIExportPathItem()
            
            // Получаем модель request body если есть
            var requestBody: OpenAPIExportRequestBody?
            if let requestBodyModelId = endpoint.requestBodyModelId,
               let requestBodyModel = try await DataModel.find(requestBodyModelId, on: database) {
                
                let schema = try createSchemaFromDataModel(requestBodyModel)
                requestBody = OpenAPIExportRequestBody(
                    description: endpoint.requestBodyDescription ?? "Request body",
                    content: [
                        "application/json": OpenAPIExportMediaType(
                            schema: schema
                        )
                    ],
                    required: endpoint.requestBodyRequired
                )
            }
            
            // Получаем параметры
            let parameters = try await createParameters(from: endpoint.parameters)
            
            // Получаем ответы
            let responses = try await createResponses(from: endpoint.responses)
            
            let operation = OpenAPIExportOperation(
                summary: endpoint.summary,
                description: endpoint.description,
                parameters: parameters,
                requestBody: requestBody,
                responses: responses,
                tags: endpoint.tags.isEmpty ? nil : endpoint.tags
            )
            
            switch endpoint.httpMethod {
            case .get:
                pathItem.get = operation
            case .post:
                pathItem.post = operation
            case .put:
                pathItem.put = operation
            case .delete:
                pathItem.delete = operation
            case .patch:
                pathItem.patch = operation
            case .head:
                pathItem.head = operation
            case .options:
                pathItem.options = operation
            }
            
            paths[endpoint.path] = pathItem
        }
        
        let servers = service.environments.list.map { env in
            OpenAPIExportServer(url: env.baseURL, description: env.description)
        }
        
        // Получаем все модели данных для сервиса
        let dataModels = try await DataModel.query(on: database)
            .filter(\.$service.$id == service.id!)
            .all()
        
        let components = try createComponents(from: dataModels)
        
        return OpenAPIExportDocument(
            openapi: "3.0.3",
            info: OpenAPIExportInfo(
                title: service.name,
                version: service.version,
                description: service.description,
                contact: OpenAPIExportContact(
                    name: service.owner,
                    email: service.contactEmail
                )
            ),
            servers: servers,
            paths: paths,
            components: components
        )
    }
    
    private func createParameters(from parameters: [APIParameter]) async throws -> [OpenAPIExportParameter] {
        return try await withThrowingTaskGroup(of: OpenAPIExportParameter?.self) { group in
            var result: [OpenAPIExportParameter] = []
            
            for param in parameters {
                group.addTask {
                    var schema: OpenAPIExportSchema
                    
                    // Если есть привязанная модель, используем её
                    if let modelId = param.dataModelId,
                       let model = try await DataModel.find(modelId, on: self.database) {
                        schema = try self.createSchemaFromDataModel(model)
                    } else if let schemaRef = param.schemaRef {
                        // Если есть $ref
                        schema = OpenAPIExportSchema(ref: schemaRef)
                    } else {
                        // Простой тип
                        schema = OpenAPIExportSchema(
                            type: param.type,
                            description: param.description
                        )
                    }
                    
                    return OpenAPIExportParameter(
                        name: param.name,
                        in: param.location.rawValue,
                        description: param.description,
                        required: param.required,
                        schema: schema,
                        example: param.example
                    )
                }
            }
            
            for try await param in group {
                if let param = param {
                    result.append(param)
                }
            }
            
            return result
        }
    }
    
    private func createResponses(from responses: [APIResponse]) async throws -> [String: OpenAPIExportResponse] {
        return try await withThrowingTaskGroup(of: (String, OpenAPIExportResponse?).self) { group in
            var result: [String: OpenAPIExportResponse] = [:]
            
            for response in responses {
                group.addTask {
                    var content: [String: OpenAPIExportMediaType]?
                    
                    // Создаем контент только если есть модель или schema
                    if let modelId = response.dataModelId,
                       let model = try await DataModel.find(modelId, on: self.database) {
                        
                        let schema = try self.createSchemaFromDataModel(model)
                        content = [
                            response.contentType: OpenAPIExportMediaType(
                                schema: schema
                            )
                        ]
                    } else if let schemaRef = response.schemaRef {
                        let schema = OpenAPIExportSchema(ref: schemaRef)
                        content = [
                            response.contentType: OpenAPIExportMediaType(
                                schema: schema
                            )
                        ]
                    } else if let schemaType = response.schemaType {
                        let schema = OpenAPIExportSchema(type: schemaType)
                        content = [
                            response.contentType: OpenAPIExportMediaType(
                                schema: schema
                            )
                        ]
                    }
                    
                    return ("\(response.statusCode)", OpenAPIExportResponse(
                        description: response.description ?? "Response",
                        content: content
                    ))
                }
            }
            
            for try await (key, response) in group {
                if let response = response {
                    result[key] = response
                }
            }
            
            return result
        }
    }
    
    private func createSchemaFromDataModel(_ model: DataModel) throws -> OpenAPIExportSchema {
        if model.isReference, let ref = model.openAPIRef {
            return OpenAPIExportSchema(ref: ref)
        }
        
        switch model.type {
        case "object":
            var properties: [String: OpenAPIExportSchema] = [:]
            var requiredProperties: [String] = []
            
            for property in model.properties {
                // Создаем схему для свойства
                let propertySchema: OpenAPIExportSchema
                
                // Проверяем если свойство ссылается на другую модель
                if let items = property.items,
                   let ref = items["$ref"] {
                    // Массив ссылок
                    propertySchema = OpenAPIExportSchema(
                        type: "array",
                        items: OpenAPIExportSchema(ref: ref)
                    )
                } else if let enumValues = property.`enum` {
                    // Enum тип
                    propertySchema = OpenAPIExportSchema(
                        type: property.type,
                        description: property.description,
                        enum: enumValues
                    )
                } else {
                    // Простой тип
                    propertySchema = OpenAPIExportSchema(
                        type: property.type,
                        description: property.description,
                        format: property.format,
                        example: property.example
                    )
                }
                
                properties[property.name] = propertySchema
                
                // Проверяем если свойство обязательное
                if property.required || model.requiredProperties.contains(property.name) {
                    requiredProperties.append(property.name)
                }
            }
            
            return OpenAPIExportSchema(
                type: "object",
                description: model.description,
                properties: properties,
                required: requiredProperties.isEmpty ? nil : requiredProperties
            )
            
        case "array":
            // Определяем тип элементов массива
            let itemsSchema: OpenAPIExportSchema
            
            if let firstProperty = model.properties.first,
               let items = firstProperty.items,
               let ref = items["$ref"] {
                itemsSchema = OpenAPIExportSchema(ref: ref)
            } else if let firstProperty = model.properties.first {
                itemsSchema = OpenAPIExportSchema(
                    type: firstProperty.type,
                    description: firstProperty.description
                )
            } else {
                itemsSchema = OpenAPIExportSchema(type: "string")
            }
            
            return OpenAPIExportSchema(
                type: "array",
                description: model.description,
                items: itemsSchema
            )
            
        case "string", "integer", "number", "boolean":
            return OpenAPIExportSchema(
                type: model.type,
                description: model.description
            )
            
        default:
            return OpenAPIExportSchema(
                type: "object",
                description: model.description
            )
        }
    }
    
    private func createComponents(from dataModels: [DataModel]) throws -> OpenAPIExportComponents {
        var schemas: [String: OpenAPIExportSchema] = [:]
        
        for model in dataModels where !model.isReference {
            let schema = try createSchemaFromDataModel(model)
            schemas[model.name] = schema
        }
        
        return OpenAPIExportComponents(schemas: schemas)
    }
}

// MARK: - Модели для экспорта OpenAPI с поддержкой components

private struct OpenAPIExportDocument: Codable {
    let openapi: String
    let info: OpenAPIExportInfo
    let servers: [OpenAPIExportServer]
    let paths: [String: OpenAPIExportPathItem]
    let components: OpenAPIExportComponents?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "openapi": openapi,
            "info": info.toDictionary(),
            "servers": servers.map { $0.toDictionary() },
            "paths": paths.mapValues { $0.toDictionary() }
        ]
        
        if let components = components, let componentsDict = components.toDictionary() {
            dict["components"] = componentsDict
        }
        
        return dict
    }
}

private struct OpenAPIExportComponents: Codable {
    let schemas: [String: OpenAPIExportSchema]?
    
    func toDictionary() -> [String: Any]? {
        var dict: [String: Any] = [:]
        
        if let schemas = schemas, !schemas.isEmpty {
            dict["schemas"] = schemas.mapValues { $0.toDictionary() }
        }
        
        return dict.isEmpty ? nil : dict
    }
}

private struct OpenAPIExportInfo: Codable {
    let title: String
    let version: String
    let description: String?
    let contact: OpenAPIExportContact?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "version": version
        ]
        
        if let description = description {
            dict["description"] = description
        }
        
        if let contact = contact, let contactDict = contact.toDictionary() {
            dict["contact"] = contactDict
        }
        
        return dict
    }
}

private struct OpenAPIExportContact: Codable {
    let name: String?
    let email: String?
    
    func toDictionary() -> [String: Any]? {
        var dict: [String: Any] = [:]
        
        if let name = name {
            dict["name"] = name
        }
        
        if let email = email {
            dict["email"] = email
        }
        
        return dict.isEmpty ? nil : dict
    }
}

private struct OpenAPIExportServer: Codable {
    let url: String
    let description: String?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["url": url]
        
        if let description = description {
            dict["description"] = description
        }
        
        return dict
    }
}

private struct OpenAPIExportPathItem: Codable {
    var get: OpenAPIExportOperation?
    var post: OpenAPIExportOperation?
    var put: OpenAPIExportOperation?
    var delete: OpenAPIExportOperation?
    var patch: OpenAPIExportOperation?
    var head: OpenAPIExportOperation?
    var options: OpenAPIExportOperation?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if let get = get {
            dict["get"] = get.toDictionary()
        }
        if let post = post {
            dict["post"] = post.toDictionary()
        }
        if let put = put {
            dict["put"] = put.toDictionary()
        }
        if let delete = delete {
            dict["delete"] = delete.toDictionary()
        }
        if let patch = patch {
            dict["patch"] = patch.toDictionary()
        }
        if let head = head {
            dict["head"] = head.toDictionary()
        }
        if let options = options {
            dict["options"] = options.toDictionary()
        }
        
        return dict
    }
}

private struct OpenAPIExportOperation: Codable {
    let summary: String?
    let description: String?
    let parameters: [OpenAPIExportParameter]?
    let requestBody: OpenAPIExportRequestBody?
    let responses: [String: OpenAPIExportResponse]
    let tags: [String]?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "responses": responses.mapValues { $0.toDictionary() }
        ]
        
        if let summary = summary {
            dict["summary"] = summary
        }
        
        if let description = description {
            dict["description"] = description
        }
        
        if let parameters = parameters {
            dict["parameters"] = parameters.map { $0.toDictionary() }
        }
        
        if let requestBody = requestBody {
            dict["requestBody"] = requestBody.toDictionary()
        }
        
        if let tags = tags {
            dict["tags"] = tags
        }
        
        return dict
    }
}

private struct OpenAPIExportParameter: Codable {
    let name: String
    let `in`: String
    let description: String?
    let required: Bool
    let schema: OpenAPIExportSchema
    let example: String?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "in": `in`,
            "required": required,
            "schema": schema.toDictionary()
        ]
        
        if let description = description {
            dict["description"] = description
        }
        
        if let example = example {
            dict["example"] = example
        }
        
        return dict
    }
}

private struct OpenAPIExportRequestBody: Codable {
    let description: String?
    let content: [String: OpenAPIExportMediaType]
    let required: Bool?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "content": content.mapValues { $0.toDictionary() }
        ]
        
        if let description = description {
            dict["description"] = description
        }
        
        if let required = required {
            dict["required"] = required
        }
        
        return dict
    }
}

private struct OpenAPIExportMediaType: Codable {
    let schema: OpenAPIExportSchema?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if let schema = schema {
            dict["schema"] = schema.toDictionary()
        }
        
        return dict
    }
}

private struct OpenAPIExportResponse: Codable {
    let description: String?
    let content: [String: OpenAPIExportMediaType]?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if let description = description {
            dict["description"] = description
        }
        
        if let content = content {
            dict["content"] = content.mapValues { $0.toDictionary() }
        }
        
        return dict
    }
}

private final class OpenAPIExportSchema: Codable {
    let type: String?
    let description: String?
    let ref: String? // $ref
    let format: String?
    let `enum`: [String]?
    let example: String?
    let properties: [String: OpenAPIExportSchema]?
    let required: [String]?
    let items: OpenAPIExportSchema?
    
    init(type: String? = nil,
         description: String? = nil,
         ref: String? = nil,
         format: String? = nil,
         `enum`: [String]? = nil,
         example: String? = nil,
         properties: [String: OpenAPIExportSchema]? = nil,
         required: [String]? = nil,
         items: OpenAPIExportSchema? = nil) {
        self.type = type
        self.description = description
        self.ref = ref
        self.format = format
        self.enum = `enum`
        self.example = example
        self.properties = properties
        self.required = required
        self.items = items
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if let ref = ref {
            dict["$ref"] = ref
            return dict // Для $ref не нужно добавлять другие поля
        }
        
        if let type = type {
            dict["type"] = type
        }
        
        if let description = description {
            dict["description"] = description
        }
        
        if let format = format {
            dict["format"] = format
        }
        
        if let `enum` = `enum` {
            dict["enum"] = `enum`
        }
        
        if let example = example {
            dict["example"] = example
        }
        
        if let properties = properties, !properties.isEmpty {
            dict["properties"] = properties.mapValues { $0.toDictionary() }
        }
        
        if let required = required, !required.isEmpty {
            dict["required"] = required
        }
        
        if let items = items {
            dict["items"] = items.toDictionary()
        }
        
        return dict
    }
}
