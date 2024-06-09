//
//  DataType.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 6/27/23.
//

import Metal
import MetalPerformanceShadersGraph

// Used for setting function constants.
public protocol MTLConvertible {
  static var mtlDataType: MTLDataType { get }
}

extension Bool: MTLConvertible {
  public static var mtlDataType: MTLDataType { .bool }
}

extension UInt16: MTLConvertible {
  public static var mtlDataType: MTLDataType { .ushort }
}

extension UInt32: MTLConvertible {
  public static var mtlDataType: MTLDataType { .uint }
}

// MARK: - TensorElement

// Uses for declaring types of tensors.
public protocol TensorElement: MTLConvertible {
    @inlinable static var shortDescription: String { get }
}

public protocol TensorFloatingPoint:
  TensorElement, BinaryFloatingPoint, SIMDScalar, Decodable, Encodable { }

#if arch(arm64)
extension Float16: TensorFloatingPoint {
  @inlinable public static var shortDescription: String {
    get {
      return "f16"
    }
  }
    
  public static var mtlDataType: MTLDataType { .half }
}
#endif

extension Float: TensorFloatingPoint {
  @inlinable public static var shortDescription: String {
    get {
      return "f32"
    }
  }
  public static var mtlDataType: MTLDataType { .float }
}

extension BFloat: TensorFloatingPoint {
  @inlinable public static var shortDescription: String {
    get {
      return "bf16"
    }
  }
  public static var mtlDataType: MTLDataType { .ushort }
}

// MARK: - MTLDataType Extensions

extension MTLDataType {
  private func unrecognizedError() -> Never {
    fatalError("MTLDataType with code \(self.rawValue) not recognized.")
  }
  
  var mps: MPSDataType {
    switch self {
    case .half: return .float16
    case .ushort: return .float16
    case .float: return .float32
    default: unrecognizedError()
    }
  }
  
//  var numpy: PythonObject {
//    let ctx = PythonContext.global
//    switch self {
//    case .half: return ctx.np.float16
//    case .ushort: return ctx.np.float16
//    case .float: return ctx.np.float32
//    default: unrecognizedError()
//    }
//  }
  
  var size: Int {
    switch self {
    case .half: return 2
    case .ushort: return 2
    case .float: return 4
    default: unrecognizedError()
    }
  }
}
