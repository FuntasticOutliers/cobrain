import ProjectDescription

let project = Project(
    name: "cobrain",
    targets: [
        .target(
            name: "cobrain",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.cobrain.app",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleIconFile": "AppIcon",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "NSScreenCaptureUsageDescription": "Cobrain captures a screenshot of your active window to understand what you're working on. No images are stored.",
                "SUFeedURL": "https://weareoutliers.github.io/cobrain/appcast.xml",
                "SUPublicEDKey": "",
            ]),
            buildableFolders: [
                "cobrain/Sources",
                "cobrain/Resources",
            ],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": false,
                "com.apple.security.network.client": true,
            ]),
            dependencies: [
                .external(name: "GRDB"),
                .external(name: "MLXVLM"),
                .external(name: "Sparkle"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "Apple Development",
                "DEVELOPMENT_TEAM": "6JS29H9GMN",
                "CODE_SIGN_STYLE": "Automatic",
            ])
        ),
        .target(
            name: "cobrainTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.cobrain.appTests",
            infoPlist: .default,
            buildableFolders: [
                "cobrain/Tests",
            ],
            dependencies: [.target(name: "cobrain")]
        ),
    ]
)
