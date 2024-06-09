//
//  Random.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 6/28/23.
//

import Accelerate
import Atomics

// Not safe to use on multiple threads simultaneously.
class RandomNumberGenerator {
  static let global = RandomNumberGenerator()
  
  var generator: BNNSRandomGenerator
  
  init() {
    self.generator = BNNSCreateRandomGenerator(
      BNNSRandomGeneratorMethodAES_CTR, nil)!
  }
  
  func fillBuffer(
    _ pointer: UnsafeMutableRawPointer,
    range: Range<Float>,
    elements: Int,
    dataType: MTLDataType
  ) {
    let _pointer = switch dataType {
    case .float:
      pointer
    case .half, .ushort:
      malloc(elements * MemoryLayout<Float>.size)!
    default:
      fatalError("Data type was not FP32, FP16, or BF16.")
    }
    
    let bufferPointer = UnsafeMutableBufferPointer(start: _pointer.assumingMemoryBound(to: Float.self), count: elements)
    var arrayDescriptor = BNNSNDArrayDescriptor(data: bufferPointer, shape: .vector(elements))!
    BNNSRandomFillUniformFloat(generator, &arrayDescriptor, range.lowerBound, range.upperBound)
    
    switch dataType {
    case .half, .ushort:
      let width = UInt(elements)
      var bufferFloat32 = vImage_Buffer(data: _pointer, height: 1, width: width, rowBytes: elements * 4)
      var bufferFloat16 = vImage_Buffer(data: pointer, height: 1, width: width, rowBytes: elements * 2)
      
      let error = vImageConvert_PlanarFtoPlanar16F(&bufferFloat32, &bufferFloat16, 0)
      
      if error != kvImageNoError {
        fatalError("Encountered error code \(error) while converting F16 to F32.")
      }
      _pointer.deallocate()
    default:
      return
    }
  }
}
