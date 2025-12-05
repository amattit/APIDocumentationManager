//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Foundation
import Yams
import Vapor

public protocol OpenAPIParserProtocol {
    func parse(from data: Data, format: OpenAPIFormat) throws -> (Service, [APIEndpoint])
    func parse(from fileURL: URL) throws -> (Service, [APIEndpoint])
}

public enum OpenAPIFormat: String, Content {
    case yaml
    case json
}

public struct OpenAPIParser: OpenAPIParserProtocol {
    private let decoder: JSONDecoder
    
    public init() {
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    public func parse(from data: Data, format: OpenAPIFormat) throws -> (Service, [APIEndpoint]) {
        let openAPIDocument: OpenAPIDocument
        
        switch format {
        case .yaml:
            let yamlString = String(data: data, encoding: .utf8) ?? ""
            openAPIDocument = try YAMLDecoder().decode(OpenAPIDocument.self, from: yamlString)
        case .json:
            openAPIDocument = try decoder.decode(OpenAPIDocument.self, from: data)
        }
        
        let service = try createService(from: openAPIDocument)
        let endpoints = try createEndpoints(from: openAPIDocument, serviceId: service.id ?? UUID())
        
        return (service, endpoints)
    }
    
    public func parse(from fileURL: URL) throws -> (Service, [APIEndpoint]) {
        let data = try Data(contentsOf: fileURL)
        let format: OpenAPIFormat = fileURL.pathExtension.lowercased() == "json" ? .json : .yaml
        return try parse(from: data, format: format)
    }
    
    private func createService(from document: OpenAPIDocument) throws -> Service {
        // Извлекаем информацию о сервисе из OpenAPI документа
        let servers = document.servers ?? []
        let environments = servers.map { server -> ServiceEnvironment in
            let envType: EnvironmentType
            if server.url.contains("stage") || server.url.contains("staging") {
                envType = .stage
            } else if server.url.contains("preprod") || server.url.contains("pre-production") {
                envType = .preprod
            } else if server.url.contains("prod") || server.url.contains("production") {
                envType = .prod
            } else {
                envType = .development
            }
            
            return ServiceEnvironment(
                type: envType,
                host: URL(string: server.url)?.host ?? server.url,
                baseURL: server.url,
                description: server.description
            )
        }
        
        return Service(
            name: document.info.title,
            version: document.info.version,
            type: .internalService, // Можно определить по домену
            department: "", // Требует дополнительной информации
            description: document.info.description,
            environments: environments,
            owner: document.info.contact?.name,
            contactEmail: document.info.contact?.email
        )
    }
    
    private func createEndpoints(from document: OpenAPIDocument, serviceId: UUID) throws -> [APIEndpoint] {
        var endpoints: [APIEndpoint] = []
        
        for (path, pathItem) in document.paths {
            for (method, operation) in pathItem.operations {
                guard let httpMethod = HTTPMethod(rawValue: method.uppercased()) else {
                    continue
                }
                
                let parameters = operation.parameters?.map { param -> APIParameter in
                    APIParameter(
                        name: param.name,
                        type: param.schema?.type ?? "string",
                        location: APIParameter.ParameterLocation(rawValue: param.`in`.rawValue) ?? .query,
                        required: param.required ?? false,
                        description: param.description,
                        example: param.example as? String
                    )
                } ?? []
                
                let responses = operation.responses.map { (code, response) -> APIResponse in
                    let statusCode = Int(code) ?? 200
                    let contentType = response.content?.keys.first ?? "application/json"
                    let schema = response.content?[contentType]?.schema?.description
                    
                    return APIResponse(
                        statusCode: statusCode,
                        description: response.description,
                        contentType: contentType,
                        schema: schema
                    )
                }
                
                let endpoint = APIEndpoint(
                    serviceId: serviceId,
                    path: path,
                    httpMethod: httpMethod,
                    summary: operation.summary,
                    description: operation.description,
                    parameters: parameters,
                    requestBody: operation.requestBody?.description,
                    responses: responses,
                    businessLogic: nil,
                    plantUMLDiagram: nil,
                    dependencies: [],
                    tags: operation.tags?.map { $0.name } ?? []
                )
                
                endpoints.append(endpoint)
            }
        }
        
        return endpoints
    }
}

// Модели для парсинга OpenAPI
private struct OpenAPIDocument: Codable {
    let openapi: String
    let info: OpenAPIInfo
    let servers: [OpenAPIServer]?
    let paths: [String: OpenAPIPathItem]
}

private struct OpenAPIInfo: Codable {
    let title: String
    let version: String
    let description: String?
    let contact: OpenAPIContact?
}

private struct OpenAPIContact: Codable {
    let name: String?
    let email: String?
    let url: String?
}

private struct OpenAPIServer: Codable {
    let url: String
    let description: String?
}

private struct OpenAPIPathItem: Codable {
    let get: OpenAPIOperation?
    let post: OpenAPIOperation?
    let put: OpenAPIOperation?
    let delete: OpenAPIOperation?
    let patch: OpenAPIOperation?
    
    var operations: [String: OpenAPIOperation] {
        var ops: [String: OpenAPIOperation] = [:]
        if let get = get { ops["get"] = get }
        if let post = post { ops["post"] = post }
        if let put = put { ops["put"] = put }
        if let delete = delete { ops["delete"] = delete }
        if let patch = patch { ops["patch"] = patch }
        return ops
    }
}

private struct OpenAPIOperation: Codable {
    let summary: String?
    let description: String?
    let parameters: [OpenAPIParameter]?
    let requestBody: OpenAPIRequestBody?
    let responses: [String: OpenAPIResponse]
    let tags: [OpenAPITag]?
}

private struct OpenAPIParameter: Codable {
    let name: String
    let `in`: ParameterLocation
    let description: String?
    let required: Bool?
    let schema: OpenAPISchema?
    let example: AnyCodable?
    
    enum ParameterLocation: String, Codable {
        case query, header, path, cookie
    }
}

private struct OpenAPIRequestBody: Codable {
    let description: String?
    let content: [String: OpenAPIMediaType]?
}

private struct OpenAPIMediaType: Codable {
    let schema: OpenAPISchema?
}

private struct OpenAPISchema: Codable {
    let type: String?
    let properties: [String: OpenAPISchema]?
    
    var description: String? {
        guard let properties = properties else { return type }
        return "\(type ?? "object"): \(properties.keys.joined(separator: ", "))"
    }
}

private struct OpenAPIResponse: Codable {
    let description: String?
    let content: [String: OpenAPIMediaType]?
}

private struct OpenAPITag: Codable {
    let name: String
    let description: String?
}

private struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues(AnyCodable.init))
        default:
            try container.encodeNil()
        }
    }
}
