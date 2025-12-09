//
//  File.swift
//  
//
//  Created by seregin-ma on 08.12.2025.
//

import Vapor
import Fluent

// MARK: Service Environment Model
public final class ServiceEnvironmentModel: Model, Content, Sendable {
    public static let schema = "service_environments"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "type")
    public var type: String
    
    @Field(key: "host")
    public var host: String
    
    @Field(key: "description")
    public var description: String?
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    @Parent(key: "service_id")
    public var service: ServiceModel
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        type: String,
        host: String,
        description: String? = nil,
        serviceID: UUID
    ) {
        self.id = id
        self.type = type
        self.host = host
        self.description = description
        self.$service.id = serviceID
    }
}

// MARK: Service Model
public final class ServiceModel: Model, Content, Sendable {
    public static let schema = "services"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "name")
    public var name: String
    
    @Field(key: "version")
    public var version: String
    
    @Field(key: "type")
    public var type: String
    
    @Field(key: "owner")
    public var owner: String
    
    @Field(key: "description")
    public var description: String?
    
    @Children(for: \.$service)
    public var environments: [ServiceEnvironmentModel]
    
    @Children(for: \.$service)
    public var apiCalls: [APICallModel]
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        name: String,
        version: String,
        type: String,
        owner: String,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.type = type
        self.owner = owner
        self.description = description
    }
}

// MARK: API Call Model
public final class APICallModel: Model, Content, Sendable {
    public static let schema = "api_calls"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "path")
    public var path: String
    
    @Field(key: "method")
    public var method: String
    
    @Field(key: "description")
    public var description: String
    
    @Field(key: "tags")
    public var tags: [String]
    
    @Parent(key: "service_id")
    public var service: ServiceModel
    
    @Children(for: \.$apiCall)
    public var parameters: [ParameterModel]
    
    @Children(for: \.$apiCall)
    public var responses: [APIResponseModel]
    
    @OptionalChild(for: \.$apiCall)
    public var requestModel: SchemaModel?
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        path: String,
        method: String,
        description: String,
        tags: [String] = [],
        serviceID: UUID
    ) {
        self.id = id
        self.path = path
        self.method = method
        self.description = description
        self.tags = tags
        self.$service.id = serviceID
    }
}

// MARK: Parameter Model
public final class ParameterModel: Model, Content, Sendable {
    public static let schema = "parameters"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "name")
    public var name: String
    
    @Field(key: "type")
    public var type: String
    
    @Field(key: "location")
    public var location: String
    
    @Field(key: "required")
    public var required: Bool
    
    @Field(key: "description")
    public var description: String?
    
    @Field(key: "example")
    public var example: String?
    
    @Parent(key: "api_call_id")
    public var apiCall: APICallModel
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        name: String,
        type: String,
        location: String,
        required: Bool,
        description: String? = nil,
        example: String? = nil,
        apiCallID: UUID
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.location = location
        self.required = required
        self.description = description
        self.example = example
        self.$apiCall.id = apiCallID
    }
}

// MARK: API Response Model
public final class APIResponseModel: Model, Content, Sendable {
    public static let schema = "api_responses"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "status_code")
    public var statusCode: Int
    
    @Field(key: "description")
    public var description: String?
    
    @Field(key: "content_type")
    public var contentType: String
    
    @Field(key: "examples")
    public var examples: [String: String]?
    
    @Field(key: "headers")
    public var headers: [String: String]?
    
    @OptionalChild(for: \.$response)
    public var schemaModel: SchemaModel?
    
    @Parent(key: "api_call_id")
    public var apiCall: APICallModel
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        statusCode: Int,
        description: String? = nil,
        contentType: String,
        examples: [String: String]? = nil,
        headers: [String: String]? = nil,
        apiCallID: UUID
    ) {
        self.id = id
        self.statusCode = statusCode
        self.description = description
        self.contentType = contentType
        self.examples = examples
        self.headers = headers
        self.$apiCall.id = apiCallID
    }
}

// MARK: Schema Model
public final class SchemaModel: Model, Content, Sendable {
    public static let schema = "schemas"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "name")
    public var name: String
    
    @Children(for: \.$schema)
    public var attributes: [SchemaAttributeModel]
    
    // запрос для вызова
    @OptionalParent(key: "api_call_id")
    public var apiCall: APICallModel?
    
    @OptionalParent(key: "api_response_id")
    public var response: APIResponseModel?
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        name: String
    ) {
        self.id = id
        self.name = name
    }
}

// MARK: Schema Attribute Model
public final class SchemaAttributeModel: Model, Content, Sendable {
    public static let schema = "schema_attributes"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "name")
    public var name: String
    
    @Field(key: "type")
    public var type: String
    
    @Field(key: "is_nullable")
    public var isNullable: Bool
    
    @Field(key: "description")
    public var description: String
    
    @Field(key: "default_value")
    public var defaultValue: String?
    
    @Parent(key: "schema_id")
    public var schema: SchemaModel
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        name: String,
        type: String,
        isNullable: Bool,
        description: String,
        defaultValue: String? = nil,
        schemaID: UUID
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isNullable = isNullable
        self.description = description
        self.defaultValue = defaultValue
        self.$schema.id = schemaID
    }
}
