// swift-tools-version: 6.3
import PackageDescription

// Abysm — typed, verified access to Objective-C runtime interoperation, built on InternedStrings.
//
// The floor is iOS 18 / macOS 15, the same as AemiSDR and the Aemi packages it sits beside. Parameter packs and
// `Synchronization` both compile there (probed in docs/diary/2026-10-20-01.md); `Span` and `InlineArray` do not,
// and are not used.
var strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

// Gated behind an environment variable so Xcode dependency builds do not collide with `-suppress-warnings`.
if Context.environment["ABYSM_WERROR"] != nil {
    strictSettings.append(.unsafeFlags(["-warnings-as-errors"]))
}

let package = Package(
    name: "Abysm",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Abysm", targets: ["Abysm"])
    ],
    dependencies: [
        // Pinned by revision, the ecosystem's mechanism (TerminalKit ADR-0005).
        .package(
            url: "https://github.com/Aemi-Studio/aemi.git",
            revision: "afc1be3d578045b381e76f6b1712a81b39956ced"
        )
    ],
    targets: [
        // The one place Objective-C is unavoidable: `NSInvocation` is unavailable to Swift, and an `NSException`
        // raised by runtime access cannot be caught from Swift at all.
        .target(name: "CAbysm", publicHeadersPath: "include"),
        .target(
            name: "Abysm",
            dependencies: [
                "CAbysm",
                .product(name: "InternedStrings", package: "aemi")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AbysmTests",
            dependencies: ["Abysm"],
            swiftSettings: strictSettings
        )
    ]
)
