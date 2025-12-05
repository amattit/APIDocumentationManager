//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Foundation
import Vapor
import Yams

public protocol OpenAPIExporterProtocol {
    func export(service: Service, endpoints: [APIEndpoint], format: OpenAPIFormat) throws -> Data
    func generateOpenAPIFile(service: Service, endpoints: [APIEndpoint], format: OpenAPIFormat) throws -> URL
}

public struct OpenAPIExporter: OpenAPIExporterProtocol {
    
    public init() {}
    
    public func export(service: Service, endpoints: [APIEndpoint], format: OpenAPIFormat) throws -> Data {
        let openAPIDocument = createOpenAPIDocument(from: service, endpoints: endpoints)
        
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
    
    public func generateOpenAPIFile(service: Service, endpoints: [APIEndpoint], format: OpenAPIFormat) throws -> URL {
        let data = try export(service: service, endpoints: endpoints, format: format)
        let fileName = "\(service.name)_v\(service.version).\(format.rawValue)"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    private func createOpenAPIDocument(from service: Service, endpoints: [APIEndpoint]) -> OpenAPIExportDocument {
        var paths: [String: OpenAPIExportPathItem] = [:]
        
        for endpoint in endpoints {
            var pathItem = paths[endpoint.path] ?? OpenAPIExportPathItem()
            
            let operation = OpenAPIExportOperation(
                summary: endpoint.summary,
                description: endpoint.description,
                parameters: endpoint.parameters.map { param in
                    OpenAPIExportParameter(
                        name: param.name,
                        in: param.location.rawValue,
                        description: param.description,
                        required: param.required,
                        schema: OpenAPIExportSchema(type: param.type),
                        example: param.example
                    )
                },
                requestBody: endpoint.requestBody.map { body in
                    OpenAPIExportRequestBody(
                        description: "Request body",
                        content: [
                            "application/json": OpenAPIExportMediaType(
                                schema: OpenAPIExportSchema(type: "object", description: body)
                            )
                        ]
                    )
                },
                responses: Dictionary(uniqueKeysWithValues: endpoint.responses.map { response in
                    let key = "\(response.statusCode)"
                    let value = OpenAPIExportResponse(
                        description: response.description ?? "Response",
                        content: [
                            response.contentType: OpenAPIExportMediaType(
                                schema: response.schema.map { OpenAPIExportSchema(description: $0) }
                            )
                        ]
                    )
                    return (key, value)
                }),
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
        
        let servers = service.environments.map { env in
            OpenAPIExportServer(url: env.baseURL, description: env.description)
        }
        
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
            paths: paths
        )
    }
}

// Модели для экспорта OpenAPI
private struct OpenAPIExportDocument: Codable {
    let openapi: String
    let info: OpenAPIExportInfo
    let servers: [OpenAPIExportServer]
    let paths: [String: OpenAPIExportPathItem]
    
    func toDictionary() -> [String: Any] {
        return [
            "openapi": openapi,
            "info": info.toDictionary(),
            "servers": servers.map { $0.toDictionary() },
            "paths": paths.mapValues { $0.toDictionary() }
        ]
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

private struct OpenAPIExportSchema: Codable {
    let type: String?
    let description: String?
    let properties: [String: OpenAPIExportSchema]?
    
    init(type: String? = nil, description: String? = nil, properties: [String: OpenAPIExportSchema]? = nil) {
        self.type = type
        self.description = description
        self.properties = properties
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if let type = type {
            dict["type"] = type
        }
        
        if let description = description {
            dict["description"] = description
        }
        
        if let properties = properties {
            dict["properties"] = properties.mapValues { $0.toDictionary() }
        }
        
        return dict
    }
}

private struct OpenAPIExportRequestBody: Codable {
    let description: String?
    let content: [String: OpenAPIExportMediaType]
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "content": content.mapValues { $0.toDictionary() }
        ]
        
        if let description = description {
            dict["description"] = description
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
