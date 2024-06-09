//
//  MatrixTransposeTest.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 7/13/23.
//

import Foundation

func showMatrixTransposeTest() {
  let M = 100
  let N = 50
  let K = 25
  let batchSize: Int? = 2
  
  var shapeA: [Int]
  var shapeB: [Int]
  var shapeC: [Int]
  if let batchSize {
    shapeA = [3, batchSize, K, M]
    shapeB = [3, batchSize, K, N]
    shapeC = [3, batchSize, M, N]
  } else {
    shapeA = [K, M]
    shapeB = [K, N]
    shapeC = [M, N]
  }
  
  typealias Real = Float32
  
  let mps_A = Tensor<Real>(shape: shapeA, randomUniform: 0..<1, backend: .mps)
  let mps_B = Tensor<Real>(shape: shapeB, randomUniform: 0..<1, backend: .mps)
  var mps_C = Tensor<Real>(zerosLike: shapeC, backend: .mps)
  _ExecutionContext.withDefaultBackend(.mps) {
    _ExecutionContext.profileCommands {
      mps_C.matmul(mps_A, mps_B, transposeA: true)
    }
  }
  
  let mfa_A = Tensor(copying: mps_A, backend: .mfa)
  let mfa_B = Tensor(copying: mps_B, backend: .mfa)
  var mfa_C = Tensor<Real>(zerosLike: shapeC, backend: .mfa)
  _ExecutionContext.withDefaultBackend(.mfa) {
    _ExecutionContext.profileCommands {
      mfa_C.matmul(mfa_A, mfa_B, transposeA: true)
    }
  }
  
//  MPL_showBackends(
//    mfa: mfa_C, mps: mps_C, numpy: py_C,
//    parameters: .init(matrixK: K, batchSize: batchSize),
//    slice: PythonObject(tupleOf: 0, 0))
//  MPL_showBackends(
//    mfa: mfa_C, mps: mps_C, numpy: py_C,
//    parameters: .init(matrixK: K, batchSize: batchSize),
//    slice: PythonObject(tupleOf: 0, 1))
//  MPL_showBackends(
//    mfa: mfa_C, mps: mps_C, numpy: py_C,
//    parameters: .init(matrixK: K, batchSize: batchSize),
//    slice: PythonObject(tupleOf: 1, 0))
}

func showMatrixBiasTest() {
#if arch(arm64)
  // 708x25x23xf32 (TTT, bias)
  // Failed test: 15x1x124x (TT)
  // Failed test: 144x927x28xf32 (TT) - nan
  
  let M = 48 // 708, 57
  let N = 25 // 25, 42
  let K = 23 // 23, 3
  let batchSize: Int? = nil // 2
  let transposeD: Bool = Bool.random() ? true : true
  
  var shapeA: [Int]
  var shapeB: [Int]
  var shapeC: [Int]
  var shapeD: [Int]
  if let batchSize {
    shapeA = [batchSize, K, M]
    shapeB = [batchSize, K, N]
    shapeC = [batchSize, M, N]
    if transposeD {
      shapeD = [batchSize, M]
    } else {
      shapeD = [batchSize, N]
    }
  } else {
    shapeA = [K, M]
    shapeB = [K, N]
    shapeC = [M, N]
    if transposeD {
      shapeD = [M]
    } else {
      shapeD = [N]
    }
  }
  
  typealias Real = Float32
  
//  let py_A = Tensor<Real>(zerosLike: shapeA, backend: .numpy)
//  let py_B = Tensor<Real>(zerosLike: shapeB, backend: .numpy)
  
  let mps_A = Tensor<Real>(shape: shapeA, randomUniform: 0..<1, backend: .mps)
  let mps_B = Tensor<Real>(shape: shapeB, randomUniform: 0..<1, backend: .mps)
  
  var mps_C = Tensor<Real>(zerosLike: shapeC, backend: .mps)
  let mps_D = Tensor<Real>(shape: shapeD, randomUniform: 0..<1, backend: .mps)
  _ExecutionContext.withDefaultBackend(.mps) {
    _ExecutionContext.profileCommands {
      mps_C.matmul(
        mps_A, mps_B, mps_D,
        transposeA: true, transposeD: transposeD, fusedBias: true)
    }
  }
  
  let mfa_A = Tensor(copying: mps_A, backend: .mfa)
  let mfa_B = Tensor(copying: mps_B, backend: .mfa)
  var mfa_C = Tensor<Real>(zerosLike: shapeC, backend: .mfa)
  let mfa_D = Tensor(copying: mps_D, backend: .mfa)
  _ExecutionContext.withDefaultBackend(.mfa) {
    _ExecutionContext.profileCommands {
      mfa_C.matmul(
        mfa_A, mfa_B, mfa_D,
        transposeA: true, transposeD: transposeD, fusedBias: true)
    }
  }
  
//  if let batchSize {
//    MPL_showBackends(
//      mfa: mfa_C, mps: mps_C, numpy: py_C,
//      parameters: .init(matrixK: K, batchSize: batchSize),
//      slice: PythonObject(0))
//    MPL_showBackends(
//      mfa: mfa_C, mps: mps_C, numpy: py_C,
//      parameters: .init(matrixK: K, batchSize: batchSize),
//      slice: PythonObject(1))
//  } else {
//    MPL_showBackends(
//      mfa: mfa_C, mps: mps_C, numpy: py_C,
//      parameters: .init(matrixK: K, batchSize: nil))
//  }
#endif
}


