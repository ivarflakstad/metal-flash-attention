//
//  main.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 6/23/23.
//
import MFALib
import ArgumentParser
import BFloat16


enum Operation: String, ExpressibleByArgument, CaseIterable {
  case attention, gemm
}

enum Datatype: String, ExpressibleByArgument, CaseIterable {
  case f32, f16, bf16
}

@main
struct BenchCLI: ParsableCommand {
  @Option(help: "Operation to bench")
  public var operation: Operation
  
  @Option(help: "Datatype")
  public var datatype: Datatype

  public func run() throws {
    switch operation {
    case .attention:
      switch datatype {
      case .f32:
          TestCaseRunner.runTests(testCases: [AttentionPerfTests<Float>()], speed: TestSpeed.veryLong)
      case .f16:
          TestCaseRunner.runTests(testCases: [AttentionPerfTests<Float16>()], speed: TestSpeed.veryLong)
      case .bf16:
          TestCaseRunner.runTests(testCases: [AttentionPerfTests<BFloat16>()], speed: TestSpeed.veryLong)
      }
    case .gemm:
      switch datatype {
      case .f32:
          TestCaseRunner.runTests(testCases: [GEMMPerfTests<Float>()], speed: TestSpeed.veryLong)
      case .f16:
          TestCaseRunner.runTests(testCases: [GEMMPerfTests<Float16>()], speed: TestSpeed.veryLong)
      case .bf16:
          TestCaseRunner.runTests(testCases: [GEMMPerfTests<BFloat16>()], speed: TestSpeed.veryLong)
      }
    }
  }
}
//let results = TestCaseRunner<Float32>.runTests(speed: TestSpeed.veryLong);
//
//
//results.forEach { (key: String, value: [Extraction]) in
//  print(key, value)
//}
