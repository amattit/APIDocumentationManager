import Vapor
import Fluent

public struct DataModelProperty: Codable, Content {
    public let name: String
    public let type: String
    public let description: String?
    public let required: Bool
    public let example: String?
    public let format: String?
    public let items: [String: String]? // Для массивов
    public let `enum`: [String]? // Для enum значений
    public let `default`: String?
    
    public init(name: String,
                type: String,
                description: String? = nil,
                required: Bool = false,
                example: String? = nil,
                format: String? = nil,
                items: [String: String]? = nil,
                `enum`: [String]? = nil,
                `default`: String? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.example = example
        self.format = format
        self.items = items
        self.enum = `enum`
        self.default = `default`
    }
}

public struct DataModelExample: Codable, Content {
    public let name: String
    public let value: String // JSON строка
    public let summary: String?
    public let description: String?
    
    public init(name: String,
                value: String,
                summary: String? = nil,
                description: String? = nil) {
        self.name = name
        self.value = value
        self.summary = summary
        self.description = description
    }
}

public final class DataModel: Model, Content {
    public static let schema = "data_models"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Parent(key: "service_id")
    public var service: Service
    
    @Parent(key: "endpoint_id")
    public var endpoint: APIEndpoint
    
    @Field(key: "name")
    public var name: String
    
    @Field(key: "title")
    public var title: String?
    
    @Field(key: "description")
    public var description: String?
    
    @Field(key: "type")
    public var type: String // "object", "array", "string", etc.
    
    @Field(key: "properties")
    public var properties: [DataModelProperty]
    
    @Field(key: "required_properties")
    public var requiredProperties: [String]
    
    @Field(key: "examples")
    public var examples: [DataModelExample]
    
    @Field(key: "is_reference")
    public var isReference: Bool // true если это ссылка на другую модель
    
    @Field(key: "referenced_model_name")
    public var referencedModelName: String? // Имя модели, на которую ссылаемся
    
    @OptionalParent(key: "referenced_model_id")
    public var referencedModel: DataModel? // Родительская модель, на которую ссылаемся
    
    @Field(key: "tags")
    public var tags: [String]
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?
    
    @Field(key: "openapi_ref")
    public var openAPIRef: String? // Исходная $ref из OpenAPI
    
    @Field(key: "source")
    public var source: String // "request", "response", "components"
    
    // Relationships
    @Children(for: \.$referencedModel)
    public var referencingModels: [DataModel]
    
    @Siblings(through: DataModelRelationship.self, from: \.$parentModel, to: \.$childModel)
    public var relatedModels: [DataModel]
    
    public init() {
        self.isReference = false
        self.source = "components"
    }
    
    public init(id: UUID? = nil,
                serviceId: UUID,
                name: String,
                title: String? = nil,
                description: String? = nil,
                type: String = "object",
                properties: [DataModelProperty] = [],
                requiredProperties: [String] = [],
                examples: [DataModelExample] = [],
                isReference: Bool = false,
                referencedModelName: String? = nil,
                referencedModelId: UUID? = nil,
                tags: [String] = [],
                openAPIRef: String? = nil,
                source: String = "components") {
        self.id = id
        self.$service.id = serviceId
        self.name = name
        self.title = title
        self.description = description
        self.type = type
        self.properties = properties
        self.requiredProperties = requiredProperties
        self.examples = examples
        self.isReference = isReference
        self.referencedModelName = referencedModelName
        self.$referencedModel.id = referencedModelId
        self.tags = tags
        self.openAPIRef = openAPIRef
        self.source = source
    }
}

// Модель для отношений many-to-many между моделями данных
public final class DataModelRelationship: Model {
    public static let schema = "data_model_relationships"
    
    @ID(key: .id)
    public var id: UUID?
    
    @Parent(key: "parent_model_id")
    public var parentModel: DataModel
    
    @Parent(key: "child_model_id")
    public var childModel: DataModel
    
    @Field(key: "relationship_type")
    public var relationshipType: String // "composition", "aggregation", "association", "reference"
    
    @Field(key: "property_name")
    public var propertyName: String? // Имя свойства, через которое происходит связь
    
    @Field(key: "description")
    public var description: String?
    
    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?
    
    public init() { }
    
    public init(id: UUID? = nil,
                parentModelId: UUID,
                childModelId: UUID,
                relationshipType: String = "association",
                propertyName: String? = nil,
                description: String? = nil) {
        self.id = id
        self.$parentModel.id = parentModelId
        self.$childModel.id = childModelId
        self.relationshipType = relationshipType
        self.propertyName = propertyName
        self.description = description
    }
}
