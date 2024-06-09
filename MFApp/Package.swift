// swift-tools-version: 5.10
//
//  Package.swift
//  MetalFlashAttention
//
//  Created by Ivar Arning Flakstad on 28/04/2024.
//

import PackageDescription

let package = Package(
  name: "MFApp",
  platforms: [
    .macOS(.v14),
    .iOS(.v16)
  ],
  targets: [
    .executableTarget(
      name: "MFApp",
      dependencies: [
        "MetalFlashAttention",
        .product(name: "AppleGPUInfo", package: "AppleGPUInfo")
      ]
    )
  ]
)
