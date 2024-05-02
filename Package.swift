// swift-tools-version: 5.10
//
//  Package.swift
//  MetalFlashAttention
//
//  Created by Ivar Arning Flakstad on 28/04/2024.
//

import Foundation
import PackageDescription

let package = Package(
  name: "MetalFlashAttention",
  platforms: [
    .macOS(.v14),
    .iOS(.v12)
  ],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
//    .library(
//        name: "MetalFlashAttention"
//    ),
    .executable(
        name: "tests",
        targets: ["MetalFlashAttentionTests"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/pvieito/PythonKit.git", branch: "master"),
    .package(url: "https://github.com/ivarflakstad/applegpuinfo.git", branch: "main"),
    .package(url: "https://github.com/apple/swift-atomics.git", branch: "main"),
    .package(url: "https://github.com/devicekit/DeviceKit", branch: "master"),
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages this package depends on.
//    .target(
//        name: "MetalFlashAttention",
//        dependencies: [
//          .product(
//            name: "DeviceKit",
//            package: "DeviceKit",
//            condition: .when(platforms: [.iOS])),
//        ],
//        path: "build"
//    ),
//    .executableTarget(
//        name: "AppleGPUInfoTool",
//        dependencies: [
//          "AppleGPUInfo",
//          .product(name: "ArgumentParser", package: "swift-argument-parser")
//        ]),
    .executableTarget(
        name: "MetalFlashAttentionTests",
        dependencies: [
          .product(
            name: "PythonKit",
            package: "PythonKit"
          ),
          .product(
            name: "AppleGPUInfo",
            package: "AppleGPUInfo"
          ),
          .product(
            name: "Atomics",
            package: "swift-atomics"
          ),
          .product(
            name: "DeviceKit",
            package: "DeviceKit"
          ),
        ],
        path: "Tests",
        resources: [.process("libMetalFlashAttention.metallib")]
    ),
  ]
)
