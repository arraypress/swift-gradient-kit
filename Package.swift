// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GradientKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        // Headless gradient-wallpaper engine: a Codable scene of signed-
        // distance shapes with colour ramps, a Metal renderer (OKLab blending,
        // domain warp, film grain, dither), palettes and a seeded generator.
        // No UI frameworks, no network.
        .library(name: "GradientKit", targets: ["GradientKit"]),
        // SwiftUI preview view on top of the engine.
        .library(name: "GradientKitUI", targets: ["GradientKitUI"]),
    ],
    targets: [
        .target(name: "GradientKit"),
        .target(name: "GradientKitUI", dependencies: ["GradientKit"]),
        .testTarget(name: "GradientKitTests", dependencies: ["GradientKit"]),
        // Renders every motif to PNG + a contact sheet; used for the README
        // images and for eyeballing changes to the recipes.
        .executableTarget(
            name: "gradientkit-samples",
            dependencies: ["GradientKit"],
            path: "Examples/Samples"
        ),
    ]
)
