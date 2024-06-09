//
//  TensorBuffer.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 6/27/23.
//

import Metal
//import PythonKit

protocol TensorBuffer {
  var shape: [Int] { get }
  var dataType: MTLDataType { get }
  var backend: TensorBackend { get }
  var pointer: UnsafeMutableRawPointer { get }
  
  // Number of elements. Cache the count because we use it a lot.
  // Shapes should never change.
  var count: Int { get }
  
  init(unsafeUninitializedShape shape: [Int], dataType: MTLDataType)
    
  func release()
}

extension TensorBuffer {
  // Number of bytes in memory.
  var allocatedSize: Int {
    self.count * dataType.size
  }
}
