import Foundation
import Vapor

public struct APIParameterData: Codable {
    public let name: String
    public let type: String
    public let location: ParameterLocation
    public let required: Bool
    public let description: String?
    public let example: String?
    
    public enum ParameterLocation: String, Codable {
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

public enum OpenAPIFormat: String, Content {
    case json = "json"
    case yaml = "yaml"
}
public protocol OpenAPIParserProtocol {
    func parse(from data: Data, format: OpenAPIFormat) throws -> (Service, [APIEndpoint])
    func parse(from fileURL: URL) throws -> (Service, [APIEndpoint])
}
public struct OpenAPIParser: OpenAPIParserProtocol {
    
    public init() {}
    
    public func parse(from data: Data, format: OpenAPIFormat) throws -> (Service, [APIEndpoint]) {
        // Парсим JSON напрямую через JSONSerialization
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let dict = jsonObject as? [String: Any] else {
            throw ParsingError.invalidFormat
        }
        
        return try parseOpenAPIDocument(from: dict)
    }
    
    public func parse(from fileURL: URL) throws -> (Service, [APIEndpoint]) {
        let data = try Data(contentsOf: fileURL)
        let format: OpenAPIFormat = fileURL.pathExtension.lowercased() == "json" ? .json : .yaml
        return try parse(from: data, format: format)
    }
    
    private func parseOpenAPIDocument(from dict: [String: Any]) throws -> (Service, [APIEndpoint]) {
        // Парсим информацию о сервисе
        guard let info = dict["info"] as? [String: Any],
              let title = info["title"] as? String,
              let version = info["version"] as? String else {
            throw ParsingError.missingRequiredFields
        }
        
        // Создаем сервис
        let service = Service(
            name: title,
            version: version,
            type: .internalService,
            department: "Unknown",
            description: info["description"] as? String,
            environments: parseServers(dict["servers"]),
            owner: (info["contact"] as? [String: String])?["name"],
            contactEmail: (info["contact"] as? [String: String])?["email"]
        )
        
        // Парсим endpoints
        guard let paths = dict["paths"] as? [String: Any] else {
            throw ParsingError.missingPaths
        }
        
        let endpoints = try parsePaths(paths, serviceId: service.id ?? UUID())
        
        return (service, endpoints)
    }
    
    private func parseServers(_ servers: Any?) -> [ServiceEnvironment] {
        guard let serversArray = servers as? [[String: Any]] else {
            return []
        }
        
        return serversArray.compactMap { server in
            guard let url = server["url"] as? String else { return nil }
            
            let envType: EnvironmentType
            let lowercasedURL = url.lowercased()
            
            if lowercasedURL.contains("stage") || lowercasedURL.contains("staging") {
                envType = .stage
            } else if lowercasedURL.contains("preprod") || lowercasedURL.contains("pre-production") {
                envType = .preprod
            } else if lowercasedURL.contains("prod") || lowercasedURL.contains("production") {
                envType = .prod
            } else {
                envType = .development
            }
            
            return ServiceEnvironment(
                type: envType,
                host: URL(string: url)?.host ?? "unknown",
                baseURL: url,
                description: server["description"] as? String
            )
        }
    }
    
    private func parsePaths(_ paths: [String: Any], serviceId: UUID) throws -> [APIEndpoint] {
        var endpoints: [APIEndpoint] = []
        
        for (path, pathData) in paths {
            guard let pathDict = pathData as? [String: Any] else { continue }
            
            for (method, operationData) in pathDict {
                guard let operationDict = operationData as? [String: Any],
                      let httpMethod = HTTPMethod(rawValue: method.uppercased()) else {
                    continue
                }
                
                let endpoint = try parseOperation(
                    path: path,
                    method: httpMethod,
                    operation: operationDict,
                    serviceId: serviceId
                )
                
                endpoints.append(endpoint)
            }
        }
        
        return endpoints
    }
    
    private func parseOperation(path: String,
                               method: HTTPMethod,
                               operation: [String: Any],
                               serviceId: UUID) throws -> APIEndpoint {
        
        // Парсим параметры
        let parameters = parseParameters(operation["parameters"])
        
        // Парсим ответы
        let responses = parseResponses(operation["responses"])
        
        // Парсим теги (обрабатываем и строки, и объекты)
        let tags = parseTags(operation["tags"])
        
        // Парсим request body
        let requestBody = parseRequestBody(operation["requestBody"])
        
        return APIEndpoint(
            serviceId: serviceId,
            path: path,
            httpMethod: method,
            summary: operation["summary"] as? String,
            description: operation["description"] as? String,
            parameters: parameters,
            requestBody: requestBody,
            responses: responses,
            businessLogic: nil,
            plantUMLDiagram: nil,
            dependencies: [],
            tags: tags
        )
    }
    
    private func parseParameters(_ parameters: Any?) -> [APIParameter] {
        guard let paramsArray = parameters as? [Any] else {
            return []
        }
        
        return paramsArray.compactMap { param in
            guard let paramDict = param as? [String: Any],
                  let name = paramDict["name"] as? String,
                  let inLocation = paramDict["in"] as? String else {
                return APIParameter(name: "", type: "", location: .query)
            }
            
            let location: APIParameter.ParameterLocation
            switch inLocation {
            case "query": location = .query
            case "path": location = .path
            case "header": location = .header
            case "cookie": location = .cookie
            default: location = .query
            }
            
            // Получаем тип из схемы
            let type: String
            if let schema = paramDict["schema"] as? [String: Any] {
                type = extractType(from: schema)
            } else {
                type = "string"
            }
            
            return APIParameter(
                name: name,
                type: type,
                location: location,
                required: paramDict["required"] as? Bool ?? false,
                description: paramDict["description"] as? String,
                example: (paramDict["example"] as? String) ?? (paramDict["example"] as? Int).map(String.init)
            )
        }
    }
    
    private func parseResponses(_ responses: Any?) -> [APIResponse] {
        guard let responsesDict = responses as? [String: Any] else {
            return []
        }
        
        return responsesDict.compactMap { (code, responseData) -> APIResponse? in
            guard let responseDict = responseData as? [String: Any] else { return nil }
            
            let statusCode = Int(code) ?? 200
            
            // Парсим контент
            var contentType = "application/json"
            var schema: String? = nil
            
            if let content = responseDict["content"] as? [String: Any],
               let (contentTypeKey, contentValue) = content.first,
               let contentDict = contentValue as? [String: Any] {
                
                contentType = contentTypeKey
                
                if let schemaDict = contentDict["schema"] as? [String: Any] {
                    schema = extractSchemaDescription(from: schemaDict)
                }
            }
            
            return APIResponse(
                statusCode: statusCode,
                description: responseDict["description"] as? String,
                contentType: contentType,
                schema: schema
            )
        }
    }
    
    private func parseTags(_ tags: Any?) -> [String] {
        let tagsArray = tags as? [Any] ?? []
        let tagsArra = tags as? String ?? ""
//        guard let tagsString = tags as? String
        
        return tagsArray.compactMap { tag in
            if let stringTag = tag as? String {
                return stringTag
            } else if let dictTag = tag as? [String: Any],
                      let name = dictTag["name"] as? String {
                return name
            }
            return nil
        }
    }
    
    private func parseRequestBody(_ requestBody: Any?) -> String? {
        guard let bodyDict = requestBody as? [String: Any],
              let content = bodyDict["content"] as? [String: Any],
              let jsonContent = content["application/json"] as? [String: Any],
              let schema = jsonContent["schema"] as? [String: Any] else {
            return nil
        }
        
        return extractSchemaDescription(from: schema)
    }
    
    private func extractType(from schema: [String: Any]) -> String {
        // Пытаемся получить тип разными способами
        if let type = schema["type"] as? String {
            return type
        }
        
        if let ref = schema["$ref"] as? String {
            return ref.components(separatedBy: "/").last ?? "object"
        }
        
        if let allOf = schema["allOf"] as? [Any], !allOf.isEmpty {
            return "object" // Сложный объект
        }
        
        if let anyOf = schema["anyOf"] as? [Any], !anyOf.isEmpty {
            return "any"
        }
        
        return "object"
    }
    
    private func extractSchemaDescription(from schema: [String: Any]) -> String {
        if let ref = schema["$ref"] as? String {
            return ref.components(separatedBy: "/").last ?? "object"
        }
        
        if let type = schema["type"] as? String {
            if type == "array", let items = schema["items"] as? [String: Any] {
                return "[\(extractSchemaDescription(from: items))]"
            }
            return type
        }
        
        if let allOf = schema["allOf"] as? [Any] {
            let descriptions = allOf.compactMap { item -> String? in
                guard let dict = item as? [String: Any] else { return nil }
                return extractSchemaDescription(from: dict)
            }
            return "allOf(\(descriptions.joined(separator: ", ")))"
        }
        
        if let anyOf = schema["anyOf"] as? [Any] {
            let descriptions = anyOf.compactMap { item -> String? in
                guard let dict = item as? [String: Any] else { return nil }
                return extractSchemaDescription(from: dict)
            }
            return "anyOf(\(descriptions.joined(separator: ", ")))"
        }
        
        return "object"
    }
}

// MARK: - Ошибки парсинга
public enum ParsingError: Error, LocalizedError {
    case invalidFormat
    case missingRequiredFields
    case missingPaths
    case invalidPathStructure
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid OpenAPI format"
        case .missingRequiredFields:
            return "Missing required fields in OpenAPI document"
        case .missingPaths:
            return "No paths found in OpenAPI document"
        case .invalidPathStructure:
            return "Invalid path structure in OpenAPI document"
        }
    }
}

// MARK: - Поддержка YAML через отдельный парсер
import Yams

public struct YAMLOpenAPIParser: OpenAPIParserProtocol {
    private let jsonParser = OpenAPIParser()
    
    public init() {}
    
    public func parse(from data: Data, format: OpenAPIFormat) throws -> (Service, [APIEndpoint]) {
        switch format {
        case .json:
            return try jsonParser.parse(from: data, format: format)
        case .yaml:
            return try parseYAML(from: data)
        }
    }
    
    public func parse(from fileURL: URL) throws -> (Service, [APIEndpoint]) {
        let data = try Data(contentsOf: fileURL)
        let format: OpenAPIFormat = fileURL.pathExtension.lowercased() == "json" ? .json : .yaml
        return try parse(from: data, format: format)
    }
    
    private func parseYAML(from data: Data) throws -> (Service, [APIEndpoint]) {
        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw ParsingError.invalidFormat
        }
        
        // Конвертируем YAML в Dictionary
        guard let yamlObject = try Yams.load(yaml: yamlString) else {
            throw ParsingError.invalidFormat
        }
        
        // Конвертируем в JSON данные для единообразной обработки
        let jsonData = try JSONSerialization.data(withJSONObject: yamlObject)
        return try jsonParser.parse(from: jsonData, format: .json)
    }
}
