// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowGym",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FlowGym",
            path: "Sources/FlowGym",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/FlowGym/Info.plist",
                ])
            ]
        )
    ]
)
