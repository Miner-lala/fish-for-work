// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XiaoYuGan",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "XiaoYuGan",
            path: "Sources/XiaoYuGan",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
