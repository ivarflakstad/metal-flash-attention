// swift-tools-version: 5.10
//
//  Package.swift
//  MetalFlashAttention
//
//  Created by Ivar Arning Flakstad on 28/04/2024.
//

import PackageDescription

let package = Package(
  name: "MFALib",
  platforms: [
    .macOS(.v14),
    .iOS(.v16)
  ],
  products: [
    .library(name: "MFALib", targets: ["MFALib"])
  ],
  dependencies: [
    .package(url: "https://github.com/philipturner/applegpuinfo.git", branch: "main"),
    .package(url: "https://github.com/apple/swift-atomics.git", branch: "main"),
//    .package(url: "https://github.com/devicekit/DeviceKit", branch: "master"),
  ],
  targets: [
    .target(
      name: "MFALib",
      dependencies: [
        .product(name: "AppleGPUInfo", package: "AppleGPUInfo"),
        .product(name: "Atomics", package: "swift-atomics"),
      ],
      resources: [.process("Resources")]
    )
  ]
)
