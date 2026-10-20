// swift-tools-version: 6.3
import PackageDescription

// Abysm — typed, verified access to private Objective-C API, built on InternedStrings.
//
// The floor is iOS 18 / macOS 15, the same as AemiSDR and the Aemi packages it sits beside. Parameter packs and
// `Synchronization` both compile there (probed in docs/diary/2026-10-20-01.md); `Span` and `InlineArray` do not,
// and are not used.
private let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error)
]

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
            revision: "70762bbd2cf97ca8aa37c1608db7b3744db21f53"
        )
    ],
    targets: [
        // The one place Objective-C is unavoidable: `NSInvocation` is unavailable to Swift, and an `NSException`
        // raised by private API cannot be caught from Swift at all.
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
