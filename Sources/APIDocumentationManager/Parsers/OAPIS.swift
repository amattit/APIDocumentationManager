//
//  File.swift
//  
//
//  Created by seregin-ma on 10.12.2025.
//

// MARK: - Основные структуры OpenAPI

import Foundation

// Корневая структура OpenAPI спецификации
struct OpenAPISpec: Codable {
    let openapi: String
    let info: APIInfo
    let paths: [String: PathItem]
    let components: Components
    
    enum CodingKeys: String, CodingKey {
        case openapi
        case info
        case paths
        case components
    }
}

// Информация об API
struct APIInfo: Codable {
    let title: String
    let version: String
}

// Компоненты схемы
struct Components: Codable {
    let schemas: [String: Schema]
    
    enum CodingKeys: String, CodingKey {
        case schemas
    }
}

// MARK: - Пути и операции

// Элемент пути
struct PathItem: Codable {
    let get: Operation?
    let post: Operation?
    let put: Operation?
    let delete: Operation?
    let patch: Operation?
    let head: Operation?
    let options: Operation?
    
    enum CodingKeys: String, CodingKey {
        case get, post, put, delete, patch, head, options
    }
}

// Операция API
struct Operation: Codable {
    let tags: [String]?
    let summary: String?
    let description: String?
    let operationId: String
    let parameters: [Parameter]?
    let requestBody: RequestBody?
    let responses: [String: Response]
    let security: [SecurityRequirement]?
    
    enum CodingKeys: String, CodingKey {
        case tags, summary, description, operationId, parameters, requestBody, responses, security
    }
}

// Параметр запроса
struct Parameter: Codable {
    let name: String
    let `in`: ParameterLocation
    let description: String?
    let required: Bool?
    let schema: Schema?
    let content: [String: MediaType]?
    
    enum CodingKeys: String, CodingKey {
        case name, `in`, description, required, schema, content
    }
}

// Тело запроса
struct RequestBody: Codable {
    let content: [String: MediaType]
    let required: Bool?
    
    enum CodingKeys: String, CodingKey {
        case content, required
    }
}

// Медиа-тип
struct MediaType: Codable {
    let schema: Schema?
    
    enum CodingKeys: String, CodingKey {
        case schema
    }
}

// Ответ API
struct Response: Codable {
    let description: String
    let content: [String: MediaType]?
    
    enum CodingKeys: String, CodingKey {
        case description, content
    }
}

// Требование безопасности
struct SecurityRequirement: Codable {
    let values: [String: [String]]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.values = try container.decode([String: [String]].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

// MARK: - Схемы данных

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if container.decodeNil() {
            self = .null
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Неизвестный тип JSON значения"
                )
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
    
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            // Форматируем double без излишних нулей
            return String(format: "%g", value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .array:
            // Для массивов используем JSON представление
            if let data = try? JSONEncoder().encode(self),
               let jsonString = String(data: data, encoding: .utf8) {
                return jsonString
            }
            return nil
        case .object:
            // Для объектов используем JSON представление
            if let data = try? JSONEncoder().encode(self),
               let jsonString = String(data: data, encoding: .utf8) {
                return jsonString
            }
            return nil
        }
    }
}

// MARK: - Schema с кастомным декодером
class Schema: Codable {
    let ref: String?
    let type: SchemaType?
    let format: String?
    let title: String?
    let description: String?
    let `enum`: [String]?
    let items: Schema?
    let properties: [String: Schema]?
    let required: [String]?
    let allOf: [Schema]?
    let anyOf: [Schema]?
    let oneOf: [Schema]?
    let maximum: Double?
    let minimum: Double?
    let exclusiveMaximum: Double?
    let exclusiveMinimum: Double?
    let maxLength: Int?
    let minLength: Int?
    let pattern: String?
    let `default`: String?  // Всегда строка после декодирования
    let nullable: Bool?
    
    enum CodingKeys: String, CodingKey {
        case ref = "$ref"
        case type, format, title, description, `enum`, items, properties, required
        case allOf, anyOf, oneOf, maximum, minimum, exclusiveMaximum, exclusiveMinimum
        case maxLength, minLength, pattern, `default`, nullable
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Декодируем простые поля
        ref = try container.decodeIfPresent(String.self, forKey: .ref)
        type = try container.decodeIfPresent(SchemaType.self, forKey: .type)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        if let value = try? container.decodeIfPresent([String].self, forKey: .enum) {
            `enum` = value
        } else if let value = try? container.decodeIfPresent([Int].self, forKey: .enum) {
            `enum` = value.map { String($0) }
        } else if let value = try? container.decodeIfPresent([Double].self, forKey: .enum) {
            `enum` = value.map { String($0) }
        } else {
            `enum` = []
        }
        
        items = try container.decodeIfPresent(Schema.self, forKey: .items)
        properties = try container.decodeIfPresent([String: Schema].self, forKey: .properties)
        required = try container.decodeIfPresent([String].self, forKey: .required)
        allOf = try container.decodeIfPresent([Schema].self, forKey: .allOf)
        anyOf = try container.decodeIfPresent([Schema].self, forKey: .anyOf)
        oneOf = try container.decodeIfPresent([Schema].self, forKey: .oneOf)
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        exclusiveMaximum = try container.decodeIfPresent(Double.self, forKey: .exclusiveMaximum)
        exclusiveMinimum = try container.decodeIfPresent(Double.self, forKey: .exclusiveMinimum)
        maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
        minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
        nullable = try container.decodeIfPresent(Bool.self, forKey: .nullable)
        
        // Кастомная обработка поля default
        if let defaultValue = try? container.decode(JSONValue.self, forKey: .default) {
            // Преобразуем любое значение в строку
            `default` = defaultValue.stringValue
        } else {
            `default` = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Кодируем простые поля
        try container.encodeIfPresent(ref, forKey: .ref)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(`enum`, forKey: .enum)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
        try container.encodeIfPresent(allOf, forKey: .allOf)
        try container.encodeIfPresent(anyOf, forKey: .anyOf)
        try container.encodeIfPresent(oneOf, forKey: .oneOf)
        try container.encodeIfPresent(maximum, forKey: .maximum)
        try container.encodeIfPresent(minimum, forKey: .minimum)
        try container.encodeIfPresent(exclusiveMaximum, forKey: .exclusiveMaximum)
        try container.encodeIfPresent(exclusiveMinimum, forKey: .exclusiveMinimum)
        try container.encodeIfPresent(maxLength, forKey: .maxLength)
        try container.encodeIfPresent(minLength, forKey: .minLength)
        try container.encodeIfPresent(pattern, forKey: .pattern)
        try container.encodeIfPresent(nullable, forKey: .nullable)
        
        // Кодируем default как JSONValue
        if let defaultString = `default` {
            // Пытаемся определить тип оригинального значения
            if let intValue = Int(defaultString) {
                try container.encode(JSONValue.int(intValue), forKey: .default)
            } else if let doubleValue = Double(defaultString) {
                try container.encode(JSONValue.double(doubleValue), forKey: .default)
            } else if let boolValue = Bool(defaultString) {
                try container.encode(JSONValue.bool(boolValue), forKey: .default)
            } else if defaultString.lowercased() == "null" {
                try container.encode(JSONValue.null, forKey: .default)
            } else {
                // Пытаемся декодировать как JSON
                if let data = defaultString.data(using: .utf8),
                   let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    try container.encode(jsonValue, forKey: .default)
                } else {
                    // Просто как строку
                    try container.encode(JSONValue.string(defaultString), forKey: .default)
                }
            }
        }
    }
}

// MARK: - SchemaType (как в предыдущем коде)
enum SchemaType: Codable, Equatable {
    case string
    case number
    case integer
    case boolean
    case array
    case object
    case custom(String)
    
    var value: String {
        switch self {
            
        case .string:
            return "string"
        case .number:
            return "number"
        case .integer:
            return "integer"
        case .boolean:
            return "boolean"
        case .array:
            return "array"
        case .object:
            return "object"
        case .custom(_):
            return "custom"
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeString = try container.decode(String.self)
        
        switch typeString {
        case "string": self = .string
        case "number": self = .number
        case "integer": self = .integer
        case "boolean": self = .boolean
        case "array": self = .array
        case "object": self = .object
        default: self = .custom(typeString)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let stringValue: String
        
        switch self {
        case .string: stringValue = "string"
        case .number: stringValue = "number"
        case .integer: stringValue = "integer"
        case .boolean: stringValue = "boolean"
        case .array: stringValue = "array"
        case .object: stringValue = "object"
        case .custom(let value): stringValue = value
        }
        
        try container.encode(stringValue)
    }
}

// MARK: - Вспомогательные функции для работы с Schema

extension Schema {
    // Получение значения default как конкретного типа
    var defaultInt: Int? {
        guard let defaultString = `default` else { return nil }
        return Int(defaultString)
    }
    
    var defaultDouble: Double? {
        guard let defaultString = `default` else { return nil }
        return Double(defaultString)
    }
    
    var defaultBool: Bool? {
        guard let defaultString = `default` else { return nil }
        return Bool(defaultString)
    }
    
    // Проверка, является ли значение default массивом или объектом JSON
    var isDefaultJSON: Bool {
        guard let defaultString = `default` else { return false }
        return defaultString.hasPrefix("[") || defaultString.hasPrefix("{")
    }
    
    // Попытка парсинга default как JSON
    func parseDefaultAsJSON<T: Decodable>(_ type: T.Type) -> T? {
        guard let defaultString = `default`,
              let data = defaultString.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(type, from: data)
    }
}


// Расположение параметра
enum ParameterLocation: String, Codable {
    case query
    case header
    case path
    case cookie
}

// MARK: - Декодер и вспомогательные функции

public class OpenAPIDecoder {
    public init() {}
    static func decode(from data: Data) throws -> OpenAPISpec {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenAPISpec.self, from: data)
    }
}

// MARK: - Вспомогательные типы для анализа спецификации

// Информация об API для удобного доступа
struct APISummary {
    let info: APIInfo
    var paths: [EndpointInfo]
    let schemas: [String: Schema]
    
    init(from spec: OpenAPISpec) {
        self.info = spec.info
        self.schemas = spec.components.schemas
        self.paths = []
        var endpoints: [EndpointInfo] = []
        
        for (path, pathItem) in spec.paths {
            let operations = extractOperations(from: pathItem, for: path)
            endpoints.append(contentsOf: operations)
        }
        
        self.paths = endpoints
    }
    
    private func extractOperations(from pathItem: PathItem, for path: String) -> [EndpointInfo] {
        var operations: [EndpointInfo] = []
        
        if let get = pathItem.get {
            operations.append(EndpointInfo(path: path, method: "GET", operation: get))
        }
        if let post = pathItem.post {
            operations.append(EndpointInfo(path: path, method: "POST", operation: post))
        }
        if let put = pathItem.put {
            operations.append(EndpointInfo(path: path, method: "PUT", operation: put))
        }
        if let delete = pathItem.delete {
            operations.append(EndpointInfo(path: path, method: "DELETE", operation: delete))
        }
        if let patch = pathItem.patch {
            operations.append(EndpointInfo(path: path, method: "PATCH", operation: patch))
        }
        
        return operations
    }
}

// Информация об эндпоинте
struct EndpointInfo {
    let path: String
    let method: String
    let operation: Operation
    
    var operationId: String {
        return operation.operationId
    }
    
    var summary: String? {
        return operation.summary
    }
    
    var tags: [String] {
        return operation.tags ?? []
    }
    
    var responses: [ResponseInfo] {
        return operation.responses.map { ResponseInfo(statusCode: $0.key, response: $0.value) }
    }
}

// Информация о ответе
struct ResponseInfo {
    let statusCode: String
    let response: Response
    
    var description: String {
        return response.description
    }
    
    var contentTypes: [String]? {
        let keys = response.content?.keys.compactMap { String($0) }
        return keys
    }
}

// MARK: - Расширения для удобства

extension OpenAPISpec {
    func getSummary() -> APISummary {
        return APISummary(from: self)
    }
}

extension Schema {
    func getSchemaName(from ref: String) -> String {
        let components = ref.components(separatedBy: "/")
        return components.last ?? ref
    }
}

// Пример использования
class OpenAPIProcessorr {
    
    static func processSpecification(_ data: Data) {
        do {
            // Декодируем спецификацию
            let spec = try OpenAPIDecoder.decode(from: data)
            
            // Получаем сводную информацию
            let summary = spec.getSummary()
            
            print("API Title: \(summary.info.title)")
            print("API Version: \(summary.info.version)")
            print("")
            
            // Группируем эндпоинты по тегам
            let endpointsByTag = Dictionary(grouping: summary.paths) { endpoint in
                endpoint.tags.first ?? "Без тега"
            }
            
            // Выводим информацию по тегам
            for (tag, endpoints) in endpointsByTag.sorted(by: { $0.key < $1.key }) {
                print("=== \(tag) ===")
                endpoints.forEach { endpoint in
                    print("\(endpoint.method) \(endpoint.path)")
                    print("  ID: \(endpoint.operationId)")
                    if let summary = endpoint.summary {
                        print("  Summary: \(summary)")
                    }
                    print("  Responses: \(endpoint.responses.map { $0.statusCode }.joined(separator: ", "))")
                    print()
                }
            }
            
            // Информация о схемах
            print("\n=== Schemas ===")
            print("Total schemas: \(summary.schemas.count)")
            
            // Пример: Получение информации о конкретной схеме
            if let refreshTokenSchema = summary.schemas["RefreshTokenResponse"] {
                print("\nRefreshTokenResponse schema:")
                if let properties = refreshTokenSchema.properties {
                    for (name, property) in properties {
                        print("  \(name): \(property.description ?? "unknown")")
                    }
                }
            }
            
        } catch {
            print("Error decoding OpenAPI spec: \(error)")
        }
    }
    
    // Функция для получения всех операций с определенным тегом
    static func getOperationsByTag(_ spec: OpenAPISpec, tag: String) -> [EndpointInfo] {
        let summary = spec.getSummary()
        return summary.paths.filter { $0.tags.contains(tag) }
    }
    
    // Функция для получения всех моделей (схем)
    static func getAllModels(_ spec: OpenAPISpec) -> [(name: String, schema: Schema)] {
        return spec.components.schemas.map { ($0.key, $0.value) }
            .sorted { $0.name < $1.name }
    }
}
