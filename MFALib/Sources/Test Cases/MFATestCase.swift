//
//  MFATestCase.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 6/27/23.
//

import Foundation

public protocol MFATestCase {
  associatedtype T: TensorElement
  
  func typeDescription() -> String
  
  func runQuickTests()
  
  func runLongTests()
  
  func runVeryLongTests() -> [Extraction]
  
//  func pass(_ function: StaticString = #function)
//  
//  func fail(_ function: StaticString = #function) {
//    var message = "Test case '\(Self.typeDescription())', "
//    message += "function '\(function)' failed."
//    print(message)
//  }
}


public struct Extraction {
  public var sizeArray: [Int]
  public var gflopsArray: [Double]
  public var title: String
  public var style: String
  
  init(
    _ tuple: (name: String, size: [Int], gflops: [Double]),
    style: String
  ) {
    self.sizeArray = tuple.size
    self.gflopsArray = tuple.gflops
    self.title = tuple.name
    self.style = style
  }
}
