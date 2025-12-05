//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Vapor
import Fluent

public enum ServiceType: String, Codable {
    case internalService = "internal"
    case externalService = "external"
}

public enum EnvironmentType: String, Codable, Content {
    case stage
    case preprod
    case prod
    case development
    case testing
}

public struct ServiceEnvironment: Content, Sendable {
    public let type: EnvironmentType
    public let host: String
    public let baseURL: String
    public let description: String?
    public let createdAt: Date
    public let updatedAt: Date
    
    public init(type: EnvironmentType, host: String, baseURL: String, description: String? = nil) {
        self.type = type
        self.host = host
        self.baseURL = baseURL
        self.description = description
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

public final class Service: Model, Content, Sendable {
    public static let schema = "services"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "name")
    public var name: String
    
    @Field(key: "version")
    public var version: String
    
    @Field(key: "type")
    public var type: ServiceType
    
    @Field(key: "department")
    public var department: String
    
    @Field(key: "description")
    public var description: String?
    
    @Field(key: "environments")
    public var environments: [ServiceEnvironment]
    
    @Field(key: "owner")
    public var owner: String?
    
    @Field(key: "contact_email")
    public var contactEmail: String?
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    @Children(for: \.$service)
    public var apiEndpoints: [APIEndpoint]
    
    public init() { }
    
    public init(id: UUID? = nil,
                name: String,
                version: String,
                type: ServiceType,
                department: String,
                description: String? = nil,
                environments: [ServiceEnvironment] = [],
                owner: String? = nil,
                contactEmail: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.type = type
        self.department = department
        self.description = description
        self.environments = environments
        self.owner = owner
        self.contactEmail = contactEmail
    }
}
