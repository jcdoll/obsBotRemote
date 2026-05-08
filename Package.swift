// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "obsBotRemote",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "obsbot-remote", targets: ["ObsbotRemoteCLI"]),
        .executable(name: "obsbot-remote-self-test", targets: ["ObsbotRemoteSelfTest"]),
        .library(name: "ObsbotRemoteCore", targets: ["ObsbotRemoteCore"]),
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
            dependencies: ["ObsbotRemoteCore"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "ObsbotRemoteSelfTest",
            dependencies: ["ObsbotRemoteCore"]
        ),
    ]
)
