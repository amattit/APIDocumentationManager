//
//  File.swift
//  
//
//  Created by seregin-ma on 05.12.2025.
//

import Foundation
import Vapor
import Fluent

public struct ServiceDependency: Content {
    public let serviceId: UUID
    public let serviceName: String
    public let apiEndpointId: UUID
    public let apiPath: String
    public let httpMethod: HTTPMethod
    public let dependencies: [APICallDependency]
    public let level: Int
}

public struct DependencyGraph: Content {
    public let rootService: Service
    public let dependencies: [ServiceDependency]
    public let graphData: GraphData
    
    public struct GraphData: Content {
        public let nodes: [GraphNode]
        public let edges: [GraphEdge]
        
        public struct GraphNode: Content {
            public let id: String
            public let label: String
            public let type: String // "service" или "endpoint"
            public let group: String?
        }
        
        public struct GraphEdge: Content {
            public let from: String
            public let to: String
            public let label: String?
            public let arrows: String // "to" или "middle"
        }
    }
}

public protocol DependencyGraphBuilderProtocol {
    func buildGraph(for service: Service, endpoints: [APIEndpoint]) async throws -> DependencyGraph
    func findTerminalEndpoints(for service: Service) async throws -> [APIEndpoint]
    func findDependencyChain(from startServiceId: UUID, to endServiceId: UUID) async throws -> [ServiceDependency]
}

public actor DependencyGraphBuilder: DependencyGraphBuilderProtocol {
    private let database: Database
    
    public init(database: Database) {
        self.database = database
    }
    
    public func buildGraph(for service: Service, endpoints: [APIEndpoint]) async throws -> DependencyGraph {
        var allDependencies: [ServiceDependency] = []
        var visitedServices: Set<UUID> = [service.id!]
        var nodes: [DependencyGraph.GraphData.GraphNode] = []
        var edges: [DependencyGraph.GraphData.GraphEdge] = []
        
        // Добавляем корневой сервис
        let rootNodeId = "service_\(service.id!)"
        nodes.append(.init(
            id: rootNodeId,
            label: service.name,
            type: "service",
            group: service.department
        ))
        
        // Обрабатываем зависимости рекурсивно
        try await processDependencies(
            for: service,
            endpoints: endpoints,
            level: 0,
            visitedServices: &visitedServices,
            allDependencies: &allDependencies,
            nodes: &nodes,
            edges: &edges
        )
        
        return DependencyGraph(
            rootService: service,
            dependencies: allDependencies,
            graphData: .init(nodes: nodes, edges: edges)
        )
    }
    
    private func processDependencies(
        for service: Service,
        endpoints: [APIEndpoint],
        level: Int,
        visitedServices: inout Set<UUID>,
        allDependencies: inout [ServiceDependency],
        nodes: inout [DependencyGraph.GraphData.GraphNode],
        edges: inout [DependencyGraph.GraphData.GraphEdge]
    ) async throws {
        let serviceId = service.id!
        let serviceNodeId = "service_\(serviceId)"
        
        for endpoint in endpoints where endpoint.$service.id == serviceId {
            let endpointNodeId = "endpoint_\(endpoint.id!)"
            
            // Добавляем ноду для endpoint
            nodes.append(.init(
                id: endpointNodeId,
                label: "\(endpoint.httpMethod.rawValue) \(endpoint.path)",
                type: "endpoint",
                group: nil
            ))
            
            // Добавляем ребро от сервиса к endpoint
            edges.append(.init(
                from: serviceNodeId,
                to: endpointNodeId,
                label: nil,
                arrows: "to"
            ))
            
            // Создаем ServiceDependency
            let dependency = ServiceDependency(
                serviceId: serviceId,
                serviceName: service.name,
                apiEndpointId: endpoint.id!,
                apiPath: endpoint.path,
                httpMethod: endpoint.httpMethod,
                dependencies: endpoint.dependencies,
                level: level
            )
            
            allDependencies.append(dependency)
            
            // Обрабатываем зависимости endpoint
            for apiDependency in endpoint.dependencies {
                if let dependencyServiceId = apiDependency.serviceId {
                    // Если сервис уже существует, находим его
                    if let dependencyService = try await Service.find(dependencyServiceId, on: database) {
                        let depServiceNodeId = "service_\(dependencyServiceId)"
                        
                        // Добавляем ноду для зависимого сервиса, если еще не добавлена
                        if !visitedServices.contains(dependencyServiceId) {
                            nodes.append(.init(
                                id: depServiceNodeId,
                                label: dependencyService.name,
                                type: "service",
                                group: dependencyService.department
                            ))
                            visitedServices.insert(dependencyServiceId)
                        }
                        
                        // Добавляем ребро от endpoint к зависимому сервису
                        edges.append(.init(
                            from: endpointNodeId,
                            to: depServiceNodeId,
                            label: apiDependency.description ?? "calls",
                            arrows: "to"
                        ))
                        
                        // Рекурсивно обрабатываем зависимости зависимого сервиса
                        let dependencyEndpoints = try await APIEndpoint.query(on: database)
                            .filter(\.$service.$id == dependencyServiceId)
                            .all()
                        
                        try await processDependencies(
                            for: dependencyService,
                            endpoints: dependencyEndpoints,
                            level: level + 1,
                            visitedServices: &visitedServices,
                            allDependencies: &allDependencies,
                            nodes: &nodes,
                            edges: &edges
                        )
                    }
                } else {
                    // Если сервис не существует, создаем временную ноду
                    let externalServiceNodeId = "external_\(apiDependency.serviceName)"
                    
                    if !nodes.contains(where: { $0.id == externalServiceNodeId }) {
                        nodes.append(.init(
                            id: externalServiceNodeId,
                            label: "\(apiDependency.serviceName) (external)",
                            type: "service",
                            group: "external"
                        ))
                    }
                    
                    edges.append(.init(
                        from: endpointNodeId,
                        to: externalServiceNodeId,
                        label: apiDependency.description ?? "calls external",
                        arrows: "to"
                    ))
                }
            }
        }
    }
    
    public func findTerminalEndpoints(for service: Service) async throws -> [APIEndpoint] {
        let endpoints = try await APIEndpoint.query(on: database)
            .filter(\.$service.$id == service.id!)
            .all()
        
        // Терминальные endpoint - те, которые не вызывают другие сервисы
        return endpoints.filter { $0.dependencies.isEmpty }
    }
    
    public func findDependencyChain(from startServiceId: UUID, to endServiceId: UUID) async throws -> [ServiceDependency] {
        var chain: [ServiceDependency] = []
        var visited: Set<UUID> = []
        
        _ = try await findChainRecursive(
            currentServiceId: startServiceId,
            targetServiceId: endServiceId,
            currentPath: [],
            visited: &visited,
            foundChain: &chain
        )
        
        return chain
    }
    
    private func findChainRecursive(
        currentServiceId: UUID,
        targetServiceId: UUID,
        currentPath: [ServiceDependency],
        visited: inout Set<UUID>,
        foundChain: inout [ServiceDependency]
    ) async throws -> Bool {
        if currentServiceId == targetServiceId {
            foundChain = currentPath
            return true
        }
        
        if visited.contains(currentServiceId) {
            return false
        }
        
        visited.insert(currentServiceId)
        
        // Получаем все endpoints текущего сервиса
        let endpoints = try await APIEndpoint.query(on: database)
            .filter(\.$service.$id == currentServiceId)
            .all()
        
        for endpoint in endpoints {
            for dependency in endpoint.dependencies {
                if let nextServiceId = dependency.serviceId {
                    var newPath = currentPath
                    newPath.append(ServiceDependency(
                        serviceId: currentServiceId,
                        serviceName: "", // Заполнится позже
                        apiEndpointId: endpoint.id!,
                        apiPath: endpoint.path,
                        httpMethod: endpoint.httpMethod,
                        dependencies: [dependency],
                        level: currentPath.count
                    ))
                    
                    if try await findChainRecursive(
                        currentServiceId: nextServiceId,
                        targetServiceId: targetServiceId,
                        currentPath: newPath,
                        visited: &visited,
                        foundChain: &foundChain
                    ) {
                        return true
                    }
                }
            }
        }
        
        return false
    }
}
