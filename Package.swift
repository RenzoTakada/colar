// swift-tools-version: 5.10
import PackageDescription

// Colar: gerenciador de clipboard para macOS. SwiftPM puro, sem projeto Xcode (scripts/bundle.sh monta o .app).
let package = Package(
    name: "Colar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Colar", targets: ["Colar"]),
        .executable(name: "colar-checks", targets: ["ColarChecks"]),
    ],
    targets: [
        // Tudo que não é a casca do app: atalho, layout de teclado, colar, painel. Testável pelo colar-checks.
        .target(
            name: "ColarCore",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon"), .linkedFramework("SwiftUI"),
                             .linkedFramework("LinkPresentation"), .linkedFramework("QuickLookUI"), .linkedFramework("Vision")]
        ),
        .executableTarget(name: "Colar", dependencies: ["ColarCore"]),
        // XCTest só vem com o Xcode completo; os checks rodam como executável comum.
        .executableTarget(name: "ColarChecks", dependencies: ["ColarCore"]),
        // Diagnóstico: renderiza o painel com o histórico real num PNG.
        .executableTarget(name: "ColarSonda", dependencies: ["ColarCore"]),
    ]
)
