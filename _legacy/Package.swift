// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TeslaCamPro",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "TeslaCamPro", targets: ["TeslaCamPro"])
  ],
  targets: [
    .executableTarget(
      name: "TeslaCamPro",
      resources: [
        .process("Resources"),
        .process("MetalShaders.metal")
      ]
    )
  ]
)
