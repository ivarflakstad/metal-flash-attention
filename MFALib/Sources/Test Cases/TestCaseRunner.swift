//
//  TestCaseRunner.swift
//  MetalFlashAttention
//
//  Created by Ivar Arning Flakstad on 20/05/2024.
//

import Foundation

public class TestCaseRunner {
  
  public static func runTests(testCases: [any MFATestCase], speed: TestSpeed) -> [String: [Extraction]] {
    var results: [String: [Extraction]] = [:];
    
    for testCase in testCases {
      switch speed {
      case .quick:
        testCase.runQuickTests()
      case .long:
        testCase.runQuickTests()
        testCase.runLongTests()
      case .veryLong:
        testCase.runQuickTests()
        testCase.runLongTests()
        results[testCase.typeDescription()] = testCase.runVeryLongTests();
      }
    }
    return results
  }
}

public enum TestSpeed {
  // Only run quick smoke tests.
  case quick
  
  // Run quick performance tests.
  case long
  
  // Run long performance tests.
  case veryLong
}
