// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shutterdrop",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "sdprobe", targets: ["sdprobe"]),
        .executable(name: "Shutterdrop", targets: ["Shutterdrop"]),
    ],
    targets: [
        .target(name: "PTPIP"),
        .target(name: "SSDP"),
        .target(name: "ShutterdropCore", dependencies: ["PTPIP", "SSDP"]),
        .executableTarget(name: "sdprobe", dependencies: ["PTPIP", "SSDP", "ShutterdropCore"]),
        .executableTarget(name: "Shutterdrop", dependencies: ["ShutterdropCore"]),
        .testTarget(name: "PTPIPTests", dependencies: ["PTPIP"]),
        .testTarget(name: "SSDPTests", dependencies: ["SSDP"]),
        .testTarget(name: "ShutterdropCoreTests", dependencies: ["ShutterdropCore"]),
    ]
)
