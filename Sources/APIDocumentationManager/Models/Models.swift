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
    
    // Метод для получения всех исходящих вызовов (через API вызовы сервиса)
    public func getOutgoingCalls(on db: Database) async throws -> [ServiceCallModel] {
        let apiCalls = try await self.$apiCalls.get(on: db)
        var allCalls: [ServiceCallModel] = []
        for apiCall in apiCalls {
            let calls = try await apiCall.$outgoingCalls.get(on: db)
            allCalls.append(contentsOf: calls)
        }
        return allCalls
    }
    
    // Метод для получения всех входящих вызовов
    public func getIncomingCalls(on db: Database) async throws -> [ServiceCallModel] {
        let apiCalls = try await self.$apiCalls.get(on: db)
        var allCalls: [ServiceCallModel] = []
        for apiCall in apiCalls {
            let calls = try await apiCall.$incomingCalls.get(on: db)
            allCalls.append(contentsOf: calls)
        }
        return allCalls
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
    
    // Связь многие-ко-многим с SchemaModel
    @Siblings(
        through: APICallRequestSchemaModel.self,
        from: \.$apiRequest,
        to: \.$schema
    )
    public var requestModels: [SchemaModel]
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    // Исходящие вызовы (к другим сервисам)
    @Children(for: \.$sourceAPICall)
    public var outgoingCalls: [ServiceCallModel]
    
    // Входящие вызовы (от других сервисов)
    @Children(for: \.$targetAPICall)
    public var incomingCalls: [ServiceCallModel]
    
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

// MARK: API Response Schema Pivot
public final class APIResponseSchemaModel: Model {
    public static let schema = "api_response_schema"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Parent(key: "api_response_id")
    public var apiResponse: APIResponseModel
    
    @Parent(key: "schema_id")
    public var schema: SchemaModel
    
    @Field(key: "schema_type")
    public var type: String?
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        apiResponseID: UUID,
        schemaID: UUID
    ) {
        self.id = id
        self.$apiResponse.id = apiResponseID
        self.$schema.id = schemaID
    }
}

// MARK: API Call Request Schema Pivot
public final class APICallRequestSchemaModel: Model {
    public static let schema = "api_call_request_schema"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Parent(key: "api_call_request_id")
    public var apiRequest: APICallModel
    
    @Parent(key: "schema_id")
    public var schema: SchemaModel
    
    @Field(key: "schema_type")
    public var type: String?
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        apiRequestId: UUID,
        schemaID: UUID
    ) {
        self.id = id
        self.$apiRequest.id = apiRequestId
        self.$schema.id = schemaID
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
    
    // Связь многие-ко-многим с SchemaModel
    @Siblings(
        through: APIResponseSchemaModel.self,
        from: \.$apiResponse,
        to: \.$schema
    )
    public var schemas: [SchemaModel]
    
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
    
    @Parent(key: "service_id")
    public var service: ServiceModel
    
    // Связь многие-ко-многим с APIResponseModel
    @Siblings(
        through: APIResponseSchemaModel.self,
        from: \.$schema,
        to: \.$apiResponse
    )
    public var apiResponses: [APIResponseModel]
    
    // Связь многие-ко-многим с APICallModel
    @Siblings(
        through: APICallRequestSchemaModel.self,
        from: \.$schema,
        to: \.$apiRequest
    )
    public var apiCalls: [APICallModel]
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        name: String,
        serviceID: UUID
    ) {
        self.id = id
        self.name = name
        self.$service.id = serviceID
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
    
    @Field(key: "of_type")
    public var ofType: String?
    
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
        schemaID: UUID,
        ofType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isNullable = isNullable
        self.description = description
        self.defaultValue = defaultValue
        self.$schema.id = schemaID
        self.ofType = ofType
    }
}

// MARK: Service Call Model - для построения графов взаимодействия сервисов
public final class ServiceCallModel: Model, Content, Sendable {
    public static let schema = "service_calls"
    
    @ID(key: .id)
    public var id: UUID?
    
    // Исходный API вызов (кто вызывает)
    @Parent(key: "source_api_call_id")
    public var sourceAPICall: APICallModel
    
    // Целевой API вызов (кого вызывают)
    @Parent(key: "target_api_call_id")
    public var targetAPICall: APICallModel
    
    // Тип взаимодействия (HTTP, gRPC, WebSocket и т.д.)
    @Field(key: "call_type")
    public var callType: String
    
    // Описание взаимодействия (опционально)
    @Field(key: "description")
    public var description: String?
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    public init() {}
    
    public init(
        id: UUID? = nil,
        sourceAPICallID: UUID,
        targetAPICallID: UUID,
        callType: String = "HTTP",
        description: String? = nil,
        callParameters: [String: String]? = nil,
        frequency: String? = nil
    ) {
        self.id = id
        self.$sourceAPICall.id = sourceAPICallID
        self.$targetAPICall.id = targetAPICallID
        self.callType = callType
        self.description = description
    }
}

extension SchemaAttributeModel {
    func printData() {
        let data = """
    name: \(name)
    type: \(type)
    isNullable: \(isNullable)
    description: \(description)
    ofType: \(ofType)
"""
        print(data)
    }
}
