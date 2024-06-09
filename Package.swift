// swift-tools-version: 5.10
//
//  Package.swift
//  MetalFlashAttention
//
//  Created by Ivar Arning Flakstad on 28/04/2024.
//

import PackageDescription

let package = Package(
  name: "MetalFlashAttention",
  platforms: [
    .macOS(.v14),
    .iOS(.v16)
  ],
  products: [
    .library(name: "MFALib", targets: ["MFALib"])
  ],
  dependencies: [
    .package(url: "https://github.com/ivarflakstad/applegpuinfo.git", branch: "main"),
    .package(url: "https://github.com/apple/swift-atomics.git", branch: "main"),
    .package(url: "https://github.com/apple/swift-argument-parser", branch: "main"),
//    .package(url: "https://github.com/devicekit/DeviceKit", branch: "master"),
  ],
  targets: [
    .target(
      name: "MFALib",
      dependencies: [
        .product(name: "AppleGPUInfo", package: "AppleGPUInfo"),
        .product(name: "Atomics", package: "swift-atomics"),
      ],
      path: "MFALib/Sources",
      resources: [.process("libMetalFlashAttention.metallib")]
    ),
    .executableTarget(
      name: "bench",
      dependencies: [
        "MFALib",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Benchmarks/Sources"
    ),
    .target(
      name: "MFApp",
      dependencies: ["MFALib"],
      path: "MFApp/Sources"
    )
  ]
)
