//
//  Tensor.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 6/27/23.
//

import Metal
import PythonKit

// Both mask types can be accelerated with block-sparse attention.
enum AttentionMask {
  case upperTriangular
  case blockSparse(Int, Float)
}

struct Tensor<Element: TensorElement> {
  var buffer: TensorBuffer
  var shape: [Int] { buffer.shape }
  var count: Int { buffer.count }
  
  private init(unsafeUninitializedShape shape: [Int], backend: TensorBackend) {
    buffer = backend.bufferObject.init(
      unsafeUninitializedShape: shape, dataType: Element.mtlDataType)
  }
  
  init(
    shape: [Int],
    randomUniform distribution: Range<Float>,
    backend: TensorBackend = .default
  ) {
    self.init(unsafeUninitializedShape: shape, backend: backend)
    if Element.mtlDataType == .ushort {
        let bufferPointer = UnsafeMutableBufferPointer(start: buffer.pointer.assumingMemoryBound(to: BFloat.self), count: count)
        for i in 1...count {
            bufferPointer[i-1] = BFloat(i);
        };
    } else {
        RandomNumberGenerator.global.fillBuffer(
          buffer.pointer, range: distribution, elements: count,
          dataType: Element.mtlDataType)
    }
  }
  
  init(zerosLike shape: [Int], backend: TensorBackend = .default) {
    self.init(unsafeUninitializedShape: shape, backend: backend)
    memset(buffer.pointer, 0, buffer.allocatedSize)
  }
  
  init(copying other: Tensor, backend: TensorBackend = .default) {
    self.init(unsafeUninitializedShape: other.shape, backend: backend)
    memcpy(buffer.pointer, other.buffer.pointer, buffer.allocatedSize)
  }
  
  init(
    slicing other: Tensor,
    indices: [Int],
    lastSlicedDim: Int,
    backend: TensorBackend = .default
  ) {
    precondition(indices.count == lastSlicedDim + 1)
    var sliceIndex = 0
    var stride = 1
    let otherShape = other.shape
    for i in (0..<lastSlicedDim).reversed() {
      sliceIndex += indices[i] * stride
      stride *= otherShape[i]
    }
    let newShape = Array(otherShape[(lastSlicedDim + 1)...])
    self.init(unsafeUninitializedShape: newShape, backend: backend)
    
    let byteStride = newShape.reduce(1, *) * Element.mtlDataType.size
    let src = other.buffer.pointer + sliceIndex * byteStride
    memcpy(buffer.pointer, src, buffer.allocatedSize)
  }
  
  init(
    assumingShape shape: [Int],
    copying other: Tensor,
    backend: TensorBackend = .default
  ) {
    self.init(unsafeUninitializedShape: shape, backend: backend)
    memcpy(buffer.pointer, other.buffer.pointer, buffer.allocatedSize)
  }
  
  init(
    shape: [Int],
    reshaping other: Tensor,
    backend: TensorBackend = .default
  ) {
    self.init(unsafeUninitializedShape: shape, backend: backend)
    assert(self.shape.reduce(1, *) == other.shape.reduce(1, *))
    memcpy(buffer.pointer, other.buffer.pointer, buffer.allocatedSize)
  }
  
  init(shape: [Int], mask: AttentionMask, backend: TensorBackend = .default)
  where Element: TensorFloatingPoint {
    self.init(unsafeUninitializedShape: shape, backend: backend)
    
    assert(shape.count >= 2)
    let leadingDimIndex = shape.count - 1
    let R = shape[leadingDimIndex - 1]
    let C = shape[leadingDimIndex - 0]
    if case .upperTriangular = mask {
      assert(R == C)
    }
    
    let B = shape[...(leadingDimIndex - 2)].reduce(1, *)
    var pointer = buffer.pointer.assumingMemoryBound(to: Element.self)
    switch mask {
    case .upperTriangular:
      for i in 0..<R - 1 {
        defer {
          pointer += C
        }
        
        // i -> (?, ?, ?, ?)
        // 1 -> (0, 0, 2, 0)
        // 2 -> (0, 0, 2, 2)
        // 3 -> (0, 0, 2, 2)
        // 4 -> (0, 2, 4, 4)
        // 5 -> (0, 2, 4, 4)
        // 6 -> (0, 2, 4, 6)
        // 7 -> (0, 2, 4, 6)
        // 8 -> (0, 4, 6, 8)
        let lowerRangeStart = 0
        let lowerRangeEnd = i / 2 * 2
        if lowerRangeStart < lowerRangeEnd {
          let len = lowerRangeEnd - lowerRangeStart
          let pattern = SIMD2<Element>(repeating: .zero)
          if Element.mtlDataType == .half || Element.mtlDataType == .ushort {
            var copy = unsafeBitCast(pattern, to: UInt32.self)
            memset_pattern4(pointer + lowerRangeStart, &copy, len * 2)
          } else {
            var copy = unsafeBitCast(pattern, to: UInt64.self)
            memset_pattern8(pointer + lowerRangeStart, &copy, len * 4)
          }
        }
        for j in lowerRangeEnd..<min(lowerRangeEnd + 2, C) {
          if j <= i {
            pointer[j] = 0
          } else {
            pointer[j] = -.greatestFiniteMagnitude
          }
        }
        
        let upperRangeStart = lowerRangeEnd + 2
        let upperRangeEnd = R / 2 * 2
        if upperRangeStart < upperRangeEnd {
          let len = upperRangeEnd - upperRangeStart
          let pattern = SIMD2<Element>(repeating: -.greatestFiniteMagnitude)
          if Element.mtlDataType == .half || Element.mtlDataType == .ushort {
            var copy = unsafeBitCast(pattern, to: UInt32.self)
            memset_pattern4(pointer + upperRangeStart, &copy, len * 2)
          } else {
            var copy = unsafeBitCast(pattern, to: UInt64.self)
            memset_pattern8(pointer + upperRangeStart, &copy, len * 4)
          }
        }
        for j in upperRangeEnd..<min(upperRangeEnd + 2, C) {
          pointer[j] = -.greatestFiniteMagnitude
        }
      }
      memset(pointer, 0, C * Element.mtlDataType.size)
      pointer += C
      pointer -= R * C
      
      // Generate one plane, then copy it to `B` planes.
      for b in 1..<B {
        let src = pointer
        let dst = pointer + b * R * C
        let len = R * C * Element.mtlDataType.size
        memcpy(dst, src, len)
      }
    case .blockSparse(let blockSize, let sparsity):
      let pattern: UnsafeMutablePointer<Element> = .allocate(capacity: C)
      defer { pattern.deallocate() }
      
      let numBlocks = (C + blockSize - 1) / blockSize
      for _ in 0..<B {
        let nextPointer = pointer + R * C
        defer {
          assert(nextPointer == pointer)
        }
        
        for r in 0..<R {
          // Generate one row, copy it to the next `blockSize` rows.
          if r % blockSize == 0 {
            for blockIndex in 0..<numBlocks {
              let isComputed = drand48() < Double(sparsity)
              let start = blockIndex * blockSize
              let end = min(start + blockSize, C)
              let value: Element = isComputed ? 0 : -.greatestFiniteMagnitude
              for c in start..<end {
                pattern[c] = value
              }
            }
          }
          memcpy(pointer, pattern, C * Element.mtlDataType.size)
          pointer += C
        }
      }
    }
  }
}

extension Tensor {
  // NOTE: Look for all the heavily-hit codepaths in the calling code; make them
  // `assert` for release mode. Anything called once remains as `precondition`.
  private func typeAndBackendMatches(_ other: Tensor<Element>) -> Bool {
    return self.buffer.backend == other.buffer.backend
  }
  
  private func backendMatches<T>(_ other: Tensor<T>) -> Bool {
    return self.buffer.backend == other.buffer.backend
  }
  
  mutating func attention(
    queries: Tensor<Element>,
    keys: Tensor<Element>,
    values: Tensor<Element>,
    mask: Tensor<Element>? = nil,
    transposeQ: Bool = false,
    transposeK: Bool = true,
    transposeV: Bool = false,
    transposeO: Bool = false,
    blockSparse: Bool = false
  ) {
    assert(self.typeAndBackendMatches(queries))
    assert(self.typeAndBackendMatches(keys))
    assert(self.typeAndBackendMatches(values))
    if let mask {
      assert(self.typeAndBackendMatches(mask))
    }
    
    let qShape = queries.shape
    let kShape = keys.shape
    let vShape = values.shape
    let oShape = self.shape
    assert(qShape.count >= 3)
    assert(qShape.count == kShape.count)
    assert(qShape.count == vShape.count)
    assert(qShape.count == oShape.count)
    
    let batchDimIndex = qShape.endIndex - 4
    if qShape.count > 3 {
      assert(qShape[...batchDimIndex] == kShape[...batchDimIndex])
      assert(qShape[...batchDimIndex] == vShape[...batchDimIndex])
      assert(qShape[...batchDimIndex] == oShape[...batchDimIndex])
    }
    
    var Q_R: Int
    var O_R: Int
    var K_C: Int
    var V_C: Int
    
    var Q_H: Int
    var K_H: Int
    var V_H: Int
    var O_H: Int
    
    var Q_D: Int
    var K_D: Int
    var V_D: Int
    var O_D: Int
    
    let leadingDimIndex = qShape.endIndex - 1
    if transposeQ {
      Q_H = qShape[leadingDimIndex - 2]
      Q_D = qShape[leadingDimIndex - 1]
      Q_R = qShape[leadingDimIndex - 0]
    } else {
      Q_R = qShape[leadingDimIndex - 2]
      Q_H = qShape[leadingDimIndex - 1]
      Q_D = qShape[leadingDimIndex - 0]
    }
    if transposeK {
      K_C = kShape[leadingDimIndex - 2]
      K_H = kShape[leadingDimIndex - 1]
      K_D = kShape[leadingDimIndex - 0]
    } else {
      K_H = kShape[leadingDimIndex - 2]
      K_D = kShape[leadingDimIndex - 1]
      K_C = kShape[leadingDimIndex - 0]
    }
    if transposeV {
      V_H = vShape[leadingDimIndex - 2]
      V_D = vShape[leadingDimIndex - 1]
      V_C = vShape[leadingDimIndex - 0]
    } else {
      V_C = vShape[leadingDimIndex - 2]
      V_H = vShape[leadingDimIndex - 1]
      V_D = vShape[leadingDimIndex - 0]
    }
    if transposeO {
      O_H = oShape[leadingDimIndex - 2]
      O_D = oShape[leadingDimIndex - 1]
      O_R = oShape[leadingDimIndex - 0]
    } else {
      O_R = oShape[leadingDimIndex - 2]
      O_H = oShape[leadingDimIndex - 1]
      O_D = oShape[leadingDimIndex - 0]
    }
    
    guard Q_R == O_R else {
      preconditionFailure("R does not match.")
    }
    guard K_C == V_C else {
      preconditionFailure("C does not match.")
    }
    guard Q_H == K_H,
          Q_H == V_H,
          Q_H == O_H else {
      preconditionFailure("H does not match.")
    }
    guard Q_D == K_D,
          Q_D == V_D,
          Q_D == O_D else {
      preconditionFailure("D does not match.")
    }
    
    let batched = (qShape.count > 3)
    var parameters = Attention_Parameters(
      dataType: Element.mtlDataType,
      R: Q_R, C: K_C, H: Q_H, D: Q_D,
      Q_trans: transposeQ, K_trans: transposeK,
      V_trans: transposeV, O_trans: transposeO,
      batched: batched, masked: mask != nil,
      blockSparse: blockSparse)
    if blockSparse {
      precondition(mask != nil, "Block sparsity requires a mask.")
    }
    
    parameters.batchDimensionsQ = queries.shape.dropLast(3)
    if let mask {
      parameters.batchDimensionsMask = mask.shape.dropLast(3)
      if batched {
        precondition(mask.shape.count == 4)
        precondition(parameters.batchDimensionsMask!.count == 1)
      } else {
        precondition(mask.shape.count == 3)
        precondition(parameters.batchDimensionsMask!.count == 0)
      }
    }
    
    let tensors = Attention_Tensors(
      q: queries.buffer,
      k: keys.buffer,
      v: values.buffer,
      o: self.buffer,
      mask: mask?.buffer)
    buffer.backend.dispatch(parameters: parameters, tensors: tensors)
  }
  
  // Sets this tensor's data to the product of the inputs.
  mutating func matmul(
    _ a: Tensor<Element>,
    _ b: Tensor<Element>,
    _ d: Tensor<Element>? = nil,
    transposeA: Bool = false,
    transposeB: Bool = false,
    transposeD: Bool = false,
    alpha: Float = 1.0,
    beta: Float = 0.0,
    fusedBias: Bool = false
  ) {
    assert(self.typeAndBackendMatches(a))
    assert(self.typeAndBackendMatches(b))
    assert(alpha == 1.0)
    assert(beta == 0.0)
    
    let aShape = a.shape
    let bShape = b.shape
    let cShape = self.shape
    assert(aShape.count >= 2 && bShape.count >= 2 && cShape.count >= 2)
    
    let la = aShape.endIndex - 1
    let lb = bShape.endIndex - 1
    var M: Int
    var A_K: Int
    var B_K: Int
    var N: Int
    if transposeA {
      A_K = aShape[la - 1]
      M = aShape[la - 0]
    } else {
      M = aShape[la - 1]
      A_K = aShape[la - 0]
    }
    if transposeB {
      N = bShape[lb - 1]
      B_K = bShape[lb - 0]
    } else {
      B_K = bShape[lb - 1]
      N = bShape[lb - 0]
    }
    precondition(A_K == B_K, "K does not match.")
    let K = A_K
    
    var batched = false
    if aShape.count > 2 {
      precondition(cShape.count > 2)
      batched = true
    }
    if cShape.count > 2 {
      precondition(aShape.count > 2)
      batched = true
    }
    
    var parameters = GEMM_Parameters(
      dataType: Element.mtlDataType,
      M: M, N: N, K: K,
      A_trans: transposeA, B_trans: transposeB, D_trans: transposeD,
      alpha: alpha, beta: beta, batched: batched,
      fused_activation: false, fused_bias: fusedBias)
    parameters.batchDimensionsA = aShape.dropLast(2)
    parameters.batchDimensionsB = bShape.dropLast(2)
    
    if !fusedBias {
      precondition(d == nil)
    } else {
      guard let d else {
        fatalError("Bias requires a D matrix.")
      }
      
      let dShape = d.shape
      precondition(dShape.count >= 1)
      if transposeD {
        precondition(dShape.last! == M)
      } else {
        precondition(dShape.last! == N)
      }
      parameters.batchDimensionsD = d.shape.dropLast(1)
    }
    
    let tensors = GEMM_Tensors(
      a: a.buffer,
      b: b.buffer,
      c: self.buffer,
      d: d?.buffer)
    buffer.backend.dispatch(parameters: parameters, tensors: tensors)
  }
  
  // TODO: Ensure all other functions are mutating, because they overwrite the
  // contents of the destination tensor.
}
