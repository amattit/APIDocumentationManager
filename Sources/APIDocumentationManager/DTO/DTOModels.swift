//
//  File.swift
//  
//
//  Created by seregin-ma on 08.12.2025.
//

import Vapor

// MARK: - Serives

public enum ServiceTypeDTO: String, Codable, Sendable  {
    case internalService = "internal"
    case externalService = "external"
}

public struct CreateServiceRequest: Content {
    public let name: String
    public let version: String
    public let type: ServiceTypeDTO
    public let owner: String
    public let description: String?
}

public struct UpdateServiceRequest: Content {
    public let name: String?
    public let version: String?
    public let type: ServiceTypeDTO?
    public let owner: String?
    public let description: String?
}

public struct CreateServiceEnv: Content {
    public let type: String
    public let host: String
}

public struct UpdateServiceEnv: Content {
    public let id: UUID
    public let type: String?
    public let host: String?
}

struct CreateAPICallRequest: Content {
    let path: String
    let method: String
    let description: String
    let tags: [String]
    let serviceID: UUID
}

struct UpdateAPICallRequest: Content {
    let path: String?
    let method: String?
    let description: String?
    let tags: [String]?
    let serviceID: UUID?
}

struct CreateSchemaRequest: Content {
    let name: String
    let attributes: [CreateAttributeRequest]?
    let serviceId: UUID
}

struct UpdateSchemaRequest: Content {
    let name: String?
    let attributes: [CreateAttributeRequest]?
}

struct CreateAttributeRequest: Content {
    let name: String
    let type: String
    let isNullable: Bool
    let description: String
    let defaultValue: String?
}

public struct LinkAPISchemaDTO: Content, Sendable {
    let apiCallId: UUID
    let schemaID: UUID
}
public struct LinkResponseSchemaDTO: Content, Sendable {
    let responseID: UUID
    let schemaID: UUID
}

public struct CreateResponseDTO: Content, Sendable {
    let statusCode: Int
    let description: String?
    let contentType: String
    let examples: [String: String]?
    let headers: [String: String]?
}

public struct SchemasByAPICallResponse: Content, Sendable {
    let requests: [SchemaModel]
    let responses: [SchemaModel]
}

public struct UpdateResponseDTO: Content, Sendable {
    let statusCode: Int?
    let description: String?
    let contentType: String?
    let examples: [String: String]?
    let headers: [String: String]?
}

public struct CreateParameterDTO: Content, Sendable {
    let name: String
    let type: String
    let location: String
    let required: Bool
    let description: String?
    let example: String?
}

public struct UpdateParameterDTO: Content, Sendable {
    let name: String?
    let type: String?
    let location: String?
    let required: Bool?
    let description: String?
    let example: String?
}
