//
//  File.swift
//  
//
//  Created by seregin-ma on 09.12.2025.
//

import Vapor
import Fluent

public struct APIDocumentationConfiguration {
    public var migrations: [AsyncMigration]
    public var collections: [RouteCollection]
    
    public static var `default`: APIDocumentationConfiguration {
        .init(
            migrations: [
                CreateServiceModelMigration(),
                CreateServiceEnvironmentModelMigration(),
                CreateAPICallModelMigration(),
                CreateParameterModelMigration(),
                CreateServiceCallModelMigration(),
                CreateAPIResponseModelMigration(),
                CreateSchemaModelMigration(),
                CreateAPIResponseSchemaMigration(),
                CreateAPICallRequestSchemaMigration(),
                CreateSchemaAttributeModelMigration(),
            ],
            collections: [
                APICallController(),
                SchemaController(),
                ServiceController(),
                OpenAPIImportController(),
                ServiceCallController(),
            ]
        )
    }
    
    public init(
        migrations: [AsyncMigration]? = nil,
        collections: [RouteCollection]? = nil
    ) {
        self.migrations = migrations ?? APIDocumentationConfiguration.default.migrations
        self.collections = collections ?? APIDocumentationConfiguration.default.collections
    }
}

public struct APIDocumentationKit {
    public static func configure(
        _ app: Application,
        configuration: APIDocumentationConfiguration = .default
    ) throws {
        for migration in configuration.migrations {
            app.migrations.add(migration)
        }
        for controller in configuration.collections {
            try controller.boot(routes: app.routes)
        }
    }
}
