// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "APIDocumentationManager",
        platforms: [
            .macOS(.v13)
        ],
        products: [
            .library(
                name: "APIDocumentationManager",
                targets: ["APIDocumentationManager"]),
        ],
        dependencies: [
            .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
            .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0"),
            .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.0.0"),
            .package(url: "https://github.com/vapor/fluent.git", from: "4.8.0"),
//            .package(url: "https://github.com/mattpolzin/OpenAPIKit.git", from: "3.0.0"),
            .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
        ],
        targets: [
            .target(
                name: "APIDocumentationManager",
                dependencies: [
                    .product(name: "Vapor", package: "vapor"),
                    .product(name: "Yams", package: "Yams"),
                    .product(name: "AsyncHTTPClient", package: "async-http-client"),
                    .product(name: "SwiftSoup", package: "SwiftSoup"),
                    .product(name: "Fluent", package: "fluent"),
//                    .product(name: "OpenAPIKit", package: "OpenAPIKit"),
//                    .product(name: "OpenAPIKit30", package: "OpenAPIKit"),
                ]
            ),
            .testTarget(
                name: "APIDocumentationManagerTests",
                dependencies: ["APIDocumentationManager"]),
        ]
)
