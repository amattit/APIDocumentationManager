//
//  File.swift
//  
//
//  Created by seregin-ma on 11.12.2025.
//

import Foundation

// MARK: - Процессор для извлечения всех схем из спецификации
class AllSchemasExtractor {
    
    // MARK: - Структуры данных
    
    struct ExtractedSchema {
        let name: String
        let schema: Schema
        let originalSchema: [String: Any]? // Сохраняем оригинальный JSON для отладки
        let isRoot: Bool // Является ли схема корневой (прямо в components.schemas)
    }
    
    // MARK: - Основная функция
    
    /// Извлекает все схемы из спецификации, включая все вложенные
    static func extractAllSchemas(from spec: OpenAPISpec) -> [ExtractedSchema] {
        var allSchemas: [ExtractedSchema] = []
        var processedSchemas = Set<String>() // Чтобы избежать дубликатов и рекурсии
        
        // Извлекаем все схемы из components.schemas (корневые)
        for (name, schema) in spec.components.schemas {
            extractSchemasRecursively(
                name: name,
                schema: schema,
                schemas: spec.components.schemas,
                allSchemas: &allSchemas,
                processedSchemas: &processedSchemas,
                isRoot: true
            )
        }
        
        return allSchemas
    }
    
    // MARK: - Рекурсивное извлечение
    
    private static func extractSchemasRecursively(
        name: String,
        schema: Schema,
        schemas: [String: Schema],
        allSchemas: inout [ExtractedSchema],
        processedSchemas: inout Set<String>,
        isRoot: Bool
    ) {
        // Проверяем, не обрабатывали ли мы уже эту схему
        guard !processedSchemas.contains(name) else { return }
        processedSchemas.insert(name)
        
        // Добавляем текущую схему
        allSchemas.append(ExtractedSchema(
            name: name,
            schema: schema,
            originalSchema: nil, // Можно сохранять оригинальный JSON если нужно
            isRoot: isRoot
        ))
    }
    
    private static func extractSchemaName(from ref: String) -> String {
        let components = ref.components(separatedBy: "/")
        return components.last ?? ref
    }
    
    // MARK: - Функция для преобразования в ваши Vapor модели
    
    /// Преобразует все извлеченные схемы в ваши Vapor модели
    static func convertToVaporModels(from schemas: [ExtractedSchema]) -> [SchemaModelData] {
        var vaporModels: [SchemaModelData] = []
        
        for extractedSchema in schemas {
            let attributes = extractAttributes(from: extractedSchema.schema)
            
            let modelData = SchemaModelData(
                name: extractedSchema.name,
                schemaType: extractedSchema.schema.type ?? .custom("object"),
                description: extractedSchema.schema.description,
                title: extractedSchema.schema.title,
                attributes: attributes,
                isRootSchema: extractedSchema.isRoot
            )
            
            vaporModels.append(modelData)
        }
        
        return vaporModels
    }
    
    private static func extractAttributes(from schema: Schema) -> [SchemaAttribute] {
        var attributes: [SchemaAttribute] = []
        
        guard let properties = schema.properties else {
            // Если нет свойств, это может быть простой тип или массив
            return createAttributeForSimpleType(schema: schema)
        }
        
        for (propertyName, propertySchema) in properties {
            let attribute = SchemaAttribute(
                name: propertyName,
                type: mapSchemaTypeToSwift(propertySchema.type),
                isNullable: propertySchema.nullable ?? false,
                description: propertySchema.description ?? "",
                defaultValue: propertySchema.default,
                format: propertySchema.format,
                enumValues: propertySchema.enum,
                required: schema.required?.contains(propertyName) ?? false
            )
            
            attributes.append(attribute)
        }
        
        return attributes
    }
    
    private static func createAttributeForSimpleType(schema: Schema) -> [SchemaAttribute] {
        let attribute = SchemaAttribute(
            name: "value",
            type: mapSchemaTypeToSwift(schema.type),
            isNullable: schema.nullable ?? false,
            description: schema.description ?? "",
            defaultValue: schema.default,
            format: schema.format,
            enumValues: schema.enum,
            required: true
        )
        
        return [attribute]
    }
    
    private static func mapSchemaTypeToSwift(_ schemaType: SchemaType?) -> String {
        guard let schemaType = schemaType else { return "Any" }
        return schemaType.value
    }
}

// MARK: - Структуры для представления данных

struct SchemaModelData {
    let name: String
    let schemaType: SchemaType
    let description: String?
    let title: String?
    let attributes: [SchemaAttribute]
    let isRootSchema: Bool
}

struct SchemaAttribute {
    let name: String
    let type: String
    let isNullable: Bool
    let description: String
    let defaultValue: String?
    let format: String?
    let enumValues: [String]?
    let required: Bool
}

// MARK: - Пример использования с вашими Vapor моделями
import Fluent

class DatabaseSchemaImporter {
    
    /// Импортирует все схемы из OpenAPI спецификации в базу данных
    static func importAllSchemasToDatabase(
        from spec: OpenAPISpec,
        serviceID: UUID,
        on database: Database) async throws {
        // Извлекаем все схемы
        let extractedSchemas = AllSchemasExtractor.extractAllSchemas(from: spec)
        
        print("📦 Found \(extractedSchemas.count) total schemas")
        
        // Создаем словарь для быстрого поиска родительских схем
        var schemaModelsByName: [String: SchemaModel] = [:]
        
        // Сначала создаем все корневые схемы (те, что в components.schemas)
        for extractedSchema in extractedSchemas where extractedSchema.isRoot {
            let schemaModel = try await createSchemaModel(
                name: extractedSchema.name,
                schema: extractedSchema.schema,
                parentName: nil,
                schemaModelsByName: &schemaModelsByName, 
                serviceID: serviceID,
                on: database
            )
            
            schemaModelsByName[extractedSchema.name] = schemaModel
        }
        print("✅ Successfully imported \(schemaModelsByName.count) schemas to database")
    }
    
    private static func createSchemaModel(
        name: String,
        schema: Schema,
        parentName: String?,
        schemaModelsByName: inout [String: SchemaModel],
        serviceID: UUID,
        on database: Database
    ) async throws -> SchemaModel {
        // Проверяем, не создали ли мы уже эту схему
        if let existingModel = schemaModelsByName[name] {
            return existingModel
        }
        
        let schemaModel = SchemaModel(
            name: name,
            serviceID: serviceID
        )
        
        try await schemaModel.save(on: database)
        
        // Создаем атрибуты
        if let properties = schema.properties {
            for (propertyName, propertySchema) in properties {
                let attributeModel = SchemaAttributeModel(
                    name: propertyName,
                    type: propertySchema.type?.value ?? propertySchema.ref?.components(separatedBy: "/").last ?? "unknown",
                    isNullable: propertySchema.nullable ?? false,
                    description: propertySchema.description ?? "",
                    defaultValue: propertySchema.default,
                    schemaID: schemaModel.id!,
                    ofType: propertySchema.items?.ref?.components(separatedBy: "/").last ?? propertySchema.items?.type?.value
                )
                try await attributeModel.save(on: database)
            }
        }
        
        // Если это простой тип или массив без свойств
        else {
            let type = mapSchemaType(schema)
            if !(schema.enum?.isEmpty ?? false) {
                let attributeModel = SchemaAttributeModel(
                    name: schema.title ?? "unknown",
                    type: "enum",
                    isNullable: schema.nullable ?? false,
                    description: schema.description ?? "",
                    defaultValue: schema.default ?? (schema.enum ?? []).joined(separator: " ||"),
                    schemaID: schemaModel.id!,
                    ofType: type.1
                )
                try await attributeModel.save(on: database)
            }
            
            
        }
        
        return schemaModel
    }
    
    private static func mapSchemaType(_ schema: Schema) -> (String, String?) {
        guard let type = schema.type else { return (schema.ref?.components(separatedBy: "/").last ?? "unknown", nil) }
        
        switch type {
        case .string:
            return ("String", nil)
        case .integer:
            return ("Int", nil)
        case .number:
            return ("Double", nil)
        case .boolean:
            return ("Bool", nil)
        case .array:
            let child = schema.items?.ref?.components(separatedBy: "/").last
            return ("Array", child)
        case .object:
            let child = schema.title
            return ("Object", child)
        case .custom(let customType):
            return (customType, nil)
        }
    }
}

