// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "obsBotRemote",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "obsbot-remote", targets: ["ObsbotRemoteCLI"]),
        .executable(name: "obsbot-remote-menu", targets: ["ObsbotRemoteMenu"]),
        .executable(name: "obsbot-remote-self-test", targets: ["ObsbotRemoteSelfTest"]),
        .library(name: "ObsbotRemoteCore", targets: ["ObsbotRemoteCore"]),
        .library(name: "ObsbotRemoteControl", targets: ["ObsbotRemoteControl"]),
    ],
    targets: [
        .target(
            name: "ObsbotRemoteUSBBridge",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .target(
            name: "ObsbotRemoteCore",
            dependencies: ["ObsbotRemoteUSBBridge"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "ObsbotRemoteCLI",
            dependencies: ["ObsbotRemoteCore", "ObsbotRemoteControl"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "ObsbotRemoteControl",
            dependencies: ["ObsbotRemoteCore"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "ObsbotRemoteMenu",
            dependencies: ["ObsbotRemoteControl"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "ObsbotRemoteSelfTest",
            dependencies: ["ObsbotRemoteCore"]
        ),
    ]
)
