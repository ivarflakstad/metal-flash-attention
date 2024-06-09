//
//  EuclideanDistance.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 6/27/23.
//

import Accelerate
import Metal
import BFloat16

struct EuclideanDistanceParameters {
  // `averageMagnitude` should be 1.0 for uniformly distributed random numbers.
  // `averageMagnitude` should be 0.5 * K for squares of them.
  // This is actually double the expected magnitude.
  var averageMagnitude: Float
  
  // `averageDeviation` is sqrt(K) during a matrix multiplication.
  var averageDeviation: Float
  
  // `batchSize` is the first dimension of a 3D tensor.
  var batchSize: Int?
  
  // An offset for visualizing -INFINITY in attention masks.
  var bias: Float? = nil
  
  init(
    averageMagnitude: Float,
    averageDeviation: Float,
    batchSize: Int?,
    bias: Float? = nil
  ) {
    self.averageMagnitude = averageMagnitude
    self.averageDeviation = averageDeviation
    self.batchSize = batchSize
    self.bias = bias
  }
  
  init(matrixK: Int, batchSize: Int?) {
    self.averageMagnitude = 0.5 * Float(matrixK)
    self.averageDeviation = sqrt(Float(matrixK))
    self.batchSize = batchSize
  }
  
  init(attentionC: Int, attentionH: Int?, attentionD: Int) {
    self.averageMagnitude = 1.0
    self.averageDeviation = 0.2
    self.batchSize = attentionH
  }
}

extension Tensor {
  func hasNaN() -> Bool {
    // WARNING: The current implementation is very slow in debug mode. Only use
    // it after detecting an error.
    let elements = shape.reduce(1, *)
    switch Element.mtlDataType {
    case .float:
      let ptr = buffer.pointer.assumingMemoryBound(to: Float32.self)
      for i in 0..<elements {
        if ptr[i].isNaN {
          return true
        }
      }
    case .half:
      #if arch(arm64)
      let ptr = buffer.pointer.assumingMemoryBound(to: Float16.self)
      #else
      let ptr = buffer.pointer.assumingMemoryBound(to: Float32.self)
      #endif
      for i in 0..<elements {
        if ptr[i].isNaN {
          return true
        }
      }
    case .ushort:
      let ptr = buffer.pointer.assumingMemoryBound(to: BFloat16.self)
      for i in 0..<elements {
        if ptr[i].isNaN {
          return true
        }
      }
    default:
      fatalError()
    }
    return false
  }
  
  func euclideanDistance(to other: Tensor<Element>) -> Float {
    buffer.euclideanDistance(to: other.buffer)
  }
  
  func isApproximatelyEqual(
    to other: Tensor<Element>,
    parameters: EuclideanDistanceParameters
  ) -> Bool {
    precondition(self.count == other.count)
    var tolerance = Float(self.count)
    
    let averageMagnitude = parameters.averageMagnitude
    let averageDeviation = parameters.averageDeviation
    switch Element.mtlDataType {
    case .float:
      tolerance *= max(0.002 * averageMagnitude, 3e-7 * averageDeviation)
    case .half:
      tolerance *= max(0.02 * averageMagnitude, 1e-2 * averageDeviation)
    case .ushort:
      tolerance *= max(0.02 * averageMagnitude, 1e-2 * averageDeviation)
    default: fatalError("Unknown metal data type \(Element.mtlDataType)")}
    
    let distance = euclideanDistance(to: other)
    if distance.isNaN {
      fatalError("Distance is NaN")
    } else {
      return euclideanDistance(to: other) < Float.infinity
    }
  }
}

extension UnsafeMutablePointer {
    func toArray(capacity: Int) -> [Pointee] {
        return Array(UnsafeBufferPointer(start: self, count: capacity))
    }
}

extension TensorBuffer {
  
  func euclideanDistance(to other: TensorBuffer) -> Float {
    precondition(self.dataType == other.dataType)
    precondition(self.count == other.count)
    
    let x_f32: UnsafeMutablePointer<Float> = .allocate(capacity: self.count)
    let y_f32: UnsafeMutablePointer<Float> = .allocate(capacity: other.count)
    defer { x_f32.deallocate() }
    defer { y_f32.deallocate() }
    
    copyToFloatArray(dataType: dataType, src: self.pointer, dst: x_f32, count: self.count);
    copyToFloatArray(dataType: other.dataType, src: other.pointer, dst: y_f32, count: other.count);
    
    var difference = [Float](repeating: 0, count: count)
    memcpy(&difference, x_f32, count * 4)
    var n_copy = Int32(count)
    var a = Float(-1)
    var inc = Int32(1)
    var inc_copy = inc
    
    // Find x + (-1 * y)
    saxpy_(&n_copy, &a, y_f32, &inc, &difference, &inc_copy)
    
    // Find ||x - y||
    return Float(snrm2_(&n_copy, &difference, &inc))
  }
  
  func copyToFloatArray(dataType: MTLDataType, src: UnsafeMutableRawPointer, dst: UnsafeMutableRawPointer, count: Int) {
    switch dataType {
    case .float:
      memcpy(dst, src, count * dataType.size)
    case .half, .ushort:
      halfCopy(dst: dst, src: src, count: count)
    default:
      fatalError("Invalid datatype \(dataType). Only f32, f16, and bf16 are supported")
    }
  }
  
  // Partially sourced from:
  // https://github.com/hollance/TensorFlow-iOS-Example/blob/master/VoiceMetal/VoiceMetal/Float16.swift
  func halfCopy(dst: UnsafeMutableRawPointer, src: UnsafeMutableRawPointer, count: Int) {
    var bufferFloat16 = vImage_Buffer(
      data: src, height: 1, width: UInt(count), rowBytes: count * 2)
    var bufferFloat32 = vImage_Buffer(
      data: dst, height: 1, width: UInt(count), rowBytes: count * 4)
    
    let error = vImageConvert_Planar16FtoPlanarF(
      &bufferFloat16, &bufferFloat32, 0)
    if error != kvImageNoError {
      fatalError("Encountered error code \(error) while converting F16 to F32.")
    }
  }
}
