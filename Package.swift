// swift-tools-version:6.0
import PackageDescription

// No third-party dependencies: keeps the binary small and the memory footprint low.
let package = Package(
    name: "noty",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Noty", targets: ["Noty"]),
        .executable(name: "noty-mcp", targets: ["noty-mcp"]),
        .library(name: "NotyKit", targets: ["NotyKit"]),
    ],
    targets: [
        // UI-free core: everything that touches the system, parses output or decides something. Unit tested.
        .target(name: "NotyKit"),
        // The menu bar + Dock app.
        .executableTarget(name: "Noty", dependencies: ["NotyKit"]),
        // Model Context Protocol server (stdio) so agents can drive the app's capabilities.
        .executableTarget(name: "noty-mcp", dependencies: ["NotyKit"]),
        .testTarget(name: "NotyKitTests", dependencies: ["NotyKit"]),
    ],
    swiftLanguageModes: [.v5]
)
