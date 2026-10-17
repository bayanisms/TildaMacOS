// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tilda",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Tilda", targets: ["Tilda"])],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")],
    targets: [
        .target(name: "TildaCore"),
        .executableTarget(name: "Tilda", dependencies: ["TildaCore", .product(name: "SwiftTerm", package: "SwiftTerm")])
    ],
    swiftLanguageModes: [.v5]
)
