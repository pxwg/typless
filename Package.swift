// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "Typless",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "Typless", targets: ["Typless"])
  ],
  targets: [
    .executableTarget(
      name: "Typless",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("Carbon"),
        .linkedFramework("Security"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "TyplessTests",
      dependencies: ["Typless"]
    ),
  ]
)
