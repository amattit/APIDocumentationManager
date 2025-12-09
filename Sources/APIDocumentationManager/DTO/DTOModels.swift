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

public enum EnvironmentTypeDTO: String, Codable, Content, Sendable {
    case stage
    case preprod
    case prod
}

public struct ServiceEnvironmentDTO: Content, Sendable, Codable {
    public let id: UUID
    public let type: EnvironmentTypeDTO
    public let host: String
    public let baseURL: String
    public let description: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct ServiceDTO: Content, Sendable {
    public let id: UUID?
    public let name: String
    public let version: String
    public let type: ServiceTypeDTO
    public let owner: String
    public let description: String?
    public let environment: ServiceEnvironmentDTO
    public let apiCalls: [APICallDTO]?
    public let createdAt: Date
    public let updatedAt: Date?
}

// MARK: - Endpoints

public enum HTTPMethod: String, Codable, Content {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
}

public struct ParameterDTO: Content, Sendable {
    public let id: UUID
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
}

public struct APIResponseDTO: Content, Sendable {
    public let id: UUID
    public let statusCode: Int
    public let description: String?
    public let contentType: String
    public let examples: [String: String]?
    public let headers: [String: String]?
    public let responseSchema: SchemaDTO?
}


public struct APICallDTO: Content, Sendable {
    public let id: UUID?
    public let path: String
    public let method: HTTPMethod
    public let description: String
    public let callParameters: [ParameterDTO]
    public let requestSchemaName: String?
    public let tags: [String]
    public let createdAt: Date?
    public let updatedAt: Date?
    public let responses: [APIResponseDTO]
}

// MARK: - Schemas

public struct SchemaDTO: Content, Sendable {
    let id: UUID
    let name: String
    let attributes: [SchemaAttributesDTO]
    let createdAt: Date
    let updatedAt: Date?
}

public struct SchemaAttributesDTO: Content, Sendable {
    let id: UUID
    public let name: String
    public let type: String
    public let isNullable: Bool
    public let description: String
    public let defaultValue: String?
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
