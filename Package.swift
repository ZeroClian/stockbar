// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StockBar",
    platforms: [.macOS(.v13)],
    products: [.library(name: "StockCore", targets: ["StockCore"]), .executable(name: "StockBar", targets: ["StockBar"])],
    targets: [
        .target(name: "StockCore"),
        .executableTarget(name: "StockBar", dependencies: ["StockCore"]),
        .testTarget(name: "StockCoreTests", dependencies: ["StockCore"]),
        .testTarget(name: "StockBarTests", dependencies: ["StockBar", "StockCore"])
    ]
)
