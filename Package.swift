// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shutterdrop",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "sdprobe", targets: ["sdprobe"]),
    ],
    targets: [
        .target(name: "PTPIP"),
        .target(name: "SSDP"),
        .executableTarget(name: "sdprobe", dependencies: ["PTPIP", "SSDP"]),
        .testTarget(name: "PTPIPTests", dependencies: ["PTPIP"]),
        .testTarget(name: "SSDPTests", dependencies: ["SSDP"]),
    ]
)
