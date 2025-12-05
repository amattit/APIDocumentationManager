//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Vapor
import Fluent

public enum HTTPMethod: String, Codable, Content {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
}

public struct APIParameter: Content {
    public let name: String
    public let type: String
    public let location: ParameterLocation
    public let required: Bool
    public let description: String?
    public let example: String?
    
    public enum ParameterLocation: String, Codable, Content {
        case query
        case path
        case header
        case cookie
    }
    
    public init(name: String,
                type: String,
                location: ParameterLocation,
                required: Bool = false,
                description: String? = nil,
                example: String? = nil) {
        self.name = name
        self.type = type
        self.location = location
        self.required = required
        self.description = description
        self.example = example
    }
}

public struct APIResponse: Content {
    public let statusCode: Int
    public let description: String?
    public let contentType: String
    public let schema: String?
    public let examples: [String: String]?
    
    public init(statusCode: Int,
                description: String? = nil,
                contentType: String = "application/json",
                schema: String? = nil,
                examples: [String: String]? = nil) {
        self.statusCode = statusCode
        self.description = description
        self.contentType = contentType
        self.schema = schema
        self.examples = examples
    }
}

public struct APICallDependency: Content {
    public let serviceId: UUID?
    public let serviceName: String
    public let endpointPath: String
    public let httpMethod: HTTPMethod
    public let description: String?
    public let isOptional: Bool
    
    public init(serviceId: UUID? = nil,
                serviceName: String,
                endpointPath: String,
                httpMethod: HTTPMethod,
                description: String? = nil,
                isOptional: Bool = false) {
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.endpointPath = endpointPath
        self.httpMethod = httpMethod
        self.description = description
        self.isOptional = isOptional
    }
}

public final class APIEndpoint: Model, Content {
    public static let schema = "api_endpoints"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Parent(key: "service_id")
    public var service: Service
    
    @Field(key: "path")
    public var path: String
    
    @Field(key: "http_method")
    public var httpMethod: HTTPMethod
    
    @Field(key: "summary")
    public var summary: String?
    
    @Field(key: "description")
    public var description: String?
    
    @Field(key: "parameters")
    public var parameters: [APIParameter]
    
    @Field(key: "request_body")
    public var requestBody: String?
    
    @Field(key: "responses")
    public var responses: [APIResponse]
    
    @Field(key: "business_logic")
    public var businessLogic: String?
    
    @Field(key: "plantuml_diagram")
    public var plantUMLDiagram: String?
    
    @Field(key: "dependencies")
    public var dependencies: [APICallDependency]
    
    @Field(key: "tags")
    public var tags: [String]
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    public init() { }
    
    public init(id: UUID? = nil,
                serviceId: UUID,
                path: String,
                httpMethod: HTTPMethod,
                summary: String? = nil,
                description: String? = nil,
                parameters: [APIParameter] = [],
                requestBody: String? = nil,
                responses: [APIResponse] = [],
                businessLogic: String? = nil,
                plantUMLDiagram: String? = nil,
                dependencies: [APICallDependency] = [],
                tags: [String] = []) {
        self.id = id
        self.$service.id = serviceId
        self.path = path
        self.httpMethod = httpMethod
        self.summary = summary
        self.description = description
        self.parameters = parameters
        self.requestBody = requestBody
        self.responses = responses
        self.businessLogic = businessLogic
        self.plantUMLDiagram = plantUMLDiagram
        self.dependencies = dependencies
        self.tags = tags
    }
}
