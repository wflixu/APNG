// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "APNG",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        // 库产品
        .library(
            name: "APNGKit",
            targets: ["APNGKit"]
        ),
        // 可执行Demo产品
        .executable(
            name: "APNGDemo",
            targets: ["APNGDemo"]
        )
    ],
    dependencies: [
    ],
    targets: [
        // 库目标
        .target(
            name: "APNGKit",
            resources: [
                .process("Resources")
            ]
        ),
        // 库测试目标
        .testTarget(
            name: "APNGKitTests",
            dependencies: ["APNGKit"],
            resources: [
                .process("Resources")
            ]
        ),
        // 可执行Demo目标
        .executableTarget(
            name: "APNGDemo",
            dependencies: ["APNGKit"],
            path: "Sources/APNGDemo",
            resources: [
                .copy("Resources/Images") ,
               .process("Resources/Assets.xcassets"),
            ]
        ),
    ]
)
