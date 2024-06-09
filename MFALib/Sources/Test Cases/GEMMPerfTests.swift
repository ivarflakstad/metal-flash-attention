//
//  PerformanceTests.swift
//  MetalFlashAttention
//
//  Created by Philip Turner on 6/27/23.
//

import Metal
import QuartzCore
import BFloat16

public class GEMMPerfTests<T: TensorElement> {
  public init() {}

  // Covers the entire range of square matrix sizes, as well as differences
  // between MFA 32x32, MFA 48x48, and MPS.
  func testGEMMSpeed(
    granularity: Int,
    trialsExtension: Int,
    A_trans: Bool = false,
    B_trans: Bool = false,
    D_trans: Bool = false,
    batchSize: Int? = nil,
    useBias: Bool = false,
    large: Bool = false
  ) -> [Extraction] {
    precondition(granularity.nonzeroBitCount == 1)
    let logProgress = true

    var segments: [Segment] = [
      Segment<T>(sizes: 1..<64, iterations: 256),
      Segment<T>(sizes: 64..<128, iterations: 256),
      Segment<T>(sizes: 128..<192, iterations: 256),
      Segment<T>(sizes: 192..<256, iterations: 128),
      Segment<T>(sizes: 256..<384, iterations: 64),
      Segment<T>(sizes: 384..<512, iterations: 32),
      Segment<T>(sizes: 512..<768, iterations: 16),
      Segment<T>(sizes: 768..<1024, iterations: 8),
    ]
    if T.self == Float.self || (batchSize ?? 1) > 1 {
      segments.append(Segment(sizes: 1024..<1537, iterations: 4))
    } else {
      segments.append(Segment(sizes: 1024..<1536, iterations: 4))
      segments.append(Segment(sizes: 1536..<2049, iterations: 2))
    }

    if large {
      var firstRange: Range<Int>
      if T.self == Float.self || (batchSize ?? 1) > 1 {
        firstRange = 1536..<3072
      } else {
        firstRange = 2048..<3072
      }
      segments = [
        Segment(
          sizes: firstRange, iterations: 2,
          granularity: 64, trialsExtension: trialsExtension),
        Segment(
          sizes: 3072..<4096, iterations: 2,
          granularity: 128, trialsExtension: trialsExtension),
        Segment(
          sizes: 4096..<5121, iterations: 2,
          granularity: 256, trialsExtension: trialsExtension),
      ]
    }
    
    for i in 0..<segments.count {
      segments[i].profile(
        granularity: segments[i].granularity ?? granularity,
        trialsExtension: segments[i].trialsExtension ?? trialsExtension,
        logProgress: logProgress,
        A_trans: A_trans, B_trans: B_trans, D_trans: D_trans,
        batchSize: batchSize, useBias: useBias)
    }

    func extract(config: Config) -> (name: String, size: [Int], gflops: [Double]) {
      var sizes: [Int] = []
      var speeds: [Double] = []
      for segment in segments {
        let flopsArray = segment.flops[config]!
        var sizeIndex = 0
        for size in segment.sizes {
          defer { sizeIndex += 1 }
          if size % (segment.granularity ?? granularity) == 0 {
            sizes.append(size)
            speeds.append(flopsArray[sizeIndex])
          }
        }
      }
      return (config.name, sizes, speeds.map { $0 / 1e9 })
    }

    // green - MFA 48x48
    // blue - MFA 32x32
    // red - MPS
    let extractions: [Extraction] = [
      Extraction(extract(config: .mps), style: "-r"),
      Extraction(extract(config: .mfa32x32), style: "-b"),
      Extraction(extract(config: .mfa48x48), style: "-g"),
    ]
    return extractions;
    //    let plt = PythonContext.global.plt
    //    for extraction in extractions {
    //      plt.plot(
    //        extraction.sizeArray, extraction.gflopsArray,
    //        extraction.style, label: extraction.title)
    //    }
    //    plt.legend(loc: "upper left")
    //    plt.xlim(0, extractions[0].sizeArray.last!)
    //    plt.ylim(0, MetalContext.global.infoDevice.flops / 1e9)
    //    plt.xlabel("Square Matrix Size")
    //    plt.ylabel("GFLOPS")
    //
    //    var configRepr = (A_trans ? "T" : "N") + (B_trans ? "T" : "N")
    //    if useBias {
    //      if D_trans {
    //        configRepr += "T"
    //      } else {
    //        configRepr += "N"
    //      }
    //    }
    //    if let batchSize {
    //      configRepr += ", \(batchSize)x Batched"
    //    }
    //    if useBias {
    //      configRepr += ", Bias"
    //    }
    //
    //    if large {
    //      plt.xlim(extractions[0].sizeArray.first!, extractions[0].sizeArray.last!)
    //    }
    //#if DEBUG
    //    let debugWarning = " (NOT USABLE FOR CI)"
    //#else
    //    let debugWarning = ""
    //#endif
    //    if T.self == Float.self {
    //      plt.title("Float32 Utilization (\(configRepr))\(debugWarning)")
    //    } else if T.self == BFloat16.self {
    //      plt.title("BFloat16 Utilization (\(configRepr))\(debugWarning)")
    //    } else {
    //      plt.title("Float16 Utilization (\(configRepr))\(debugWarning)")
    //    }
    //    plt.show()
    //  }
  }
}

extension GEMMPerfTests: MFATestCase {

  public typealias T = T

  public func typeDescription() -> String {
    "GemmPerfTests"
  }

  public func runQuickTests() {}

  public func runLongTests() {}

  public func runVeryLongTests() -> [Extraction] {
    // Tests the precision you set as the global testing precision. For a quick
    // smoke test, you can set a larger granularity.
    return testGEMMSpeed(
      granularity: 8, trialsExtension: 2,
      B_trans: false, D_trans: false,
      batchSize: nil, useBias: false,
      large: false)
  }
}

enum Config: CaseIterable {
  // Ordered from fastest to slowest at large matrix sizes.
  case mfa48x48
  case mfa32x32
  case mps

  static var fastConfigs: [Config] { [.mfa48x48, .mfa32x32, .mps] }

  var backend: TensorBackend {
    if self == .mps { return .mps }
    else { return .mfa }
  }

  var name: String {
    switch self {
    case .mfa48x48: return "MFA 48x48"
    case .mfa32x32: return "MFA 32x32"
    case .mps: return "MPS"
    }
  }

  func prepare<T: TensorElement>() -> T? {
    _ExecutionContext.defaultBackend = self.backend
    if self == .mfa32x32 {
      let M_simd = MFA_GEMM.functionConstants["M_simd"] as! UInt16
      let N_simd = MFA_GEMM.functionConstants["N_simd"] as! UInt16
      let K_simd = MFA_GEMM.functionConstants["K_simd"] as! UInt16
      precondition(M_simd == 16)
      precondition(N_simd == 16)
      precondition(K_simd == 32)
    }
    if self == .mfa48x48 {
      MFA_Backend.global.cache.clear()
      MFA_GEMM.functionConstants["M_simd"] = UInt16(24)
      MFA_GEMM.functionConstants["N_simd"] = UInt16(24)
      let K_simd = (T.self == Float.self) ? 24 : 32
      MFA_GEMM.functionConstants["K_simd"] = UInt16(K_simd)
    }

    return nil
  }

  func cleanup() {
    _ExecutionContext.defaultBackend = .mps
    if self == .mfa48x48 {
      MFA_Backend.global.cache.clear()
      MFA_GEMM.functionConstants["M_simd"] = UInt16(16)
      MFA_GEMM.functionConstants["N_simd"] = UInt16(16)
      MFA_GEMM.functionConstants["K_simd"] = UInt16(32)
    }
  }
}

struct Segment<T: TensorElement> {
  var sizes: Range<Int>
  var iterations: Int
  var flops: [Config: [Double]] = [:]
  var currentConfig: Config?

  var granularity: Int?
  var trialsExtension: Int?

  init(
    sizes: Range<Int>,
    iterations: Int,
    granularity: Int? = nil,
    trialsExtension: Int? = nil
  ) {
    self.sizes = sizes
    self.iterations = iterations
    self.granularity = granularity
    self.trialsExtension = trialsExtension

    flops[.mfa48x48] = []
    flops[.mfa32x32] = []
    flops[.mps] = []
  }

  mutating func prepare(config: Config) {
    self.currentConfig = config
    let _: T? = config.prepare()
  }

  mutating func cleanup(config: Config) {
    config.cleanup()
    self.currentConfig = nil
  }

  mutating func _profile(
    sizes: Range<Int>, granularity: Int,
    trialsExtension: Int, isInitial: Bool,
    A_trans: Bool, B_trans: Bool, D_trans: Bool,
    batchSize: Int?, useBias: Bool
  ) {
    func innerLoop(size: Int, reportResults: Bool) {
      typealias Inner = T;
      // MPS GEMM does not (currently) support BFloat16
      if currentConfig == .mps && T.self == BFloat16.self {
        typealias Inner = Float;
      }

      if size % granularity != 0 {
        if !isInitial && reportResults {
          self.flops[currentConfig!]!.append(0)
        }
        return
      }

      var iterations = self.iterations
      var trials = 0
      SquareMatrixBenchmark_configure(&iterations, &trials)
      if isInitial {
        iterations = 1
        trials = 1
      } else {
        if currentConfig == .mps {
          // Too little sequential throughput.
          iterations = min(32, iterations)
        } else {
          trials *= trialsExtension
        }
      }

      let M = size
      let N = size
      let K = size
      var shapeA = A_trans ? [K, M] : [M, K]
      var shapeB = B_trans ? [N, K] : [K, N]
      var shapeC = [M, N]
      var shapeD = D_trans ? [M] : [N]
      if let batchSize {
        shapeA = [batchSize] + shapeA
        if shapeA.last! % 3 == 0 {
          shapeB = [1] + shapeB
        }
        if shapeA.last! % 5 == 0 {
          shapeD = [1] + shapeD
        }
        shapeC = [batchSize] + shapeC
      }

      let py_A = Tensor<Inner>(
        shape: shapeA, randomUniform: 0..<1, backend: .mps)
      let py_B = Tensor<Inner>(
        shape: shapeB, randomUniform: 0..<1, backend: .mps)
      var py_D: Tensor<Inner>?
      if useBias {
        py_D = Tensor<Inner>(
          shape: shapeD, randomUniform: 0..<1, backend: .mps)
      }

      let A = Tensor(copying: py_A)
      let B = Tensor(copying: py_B)
      var C = Tensor<Inner>(zerosLike: shapeC)
      var D: Tensor<Inner>?
      if useBias {
        D = Tensor<Inner>(copying: py_D!)
      }

      let backend = TensorBackend.default
      if isInitial {
        _ExecutionContext.executeExpression {
          backend.markFirstCommand()
          C.matmul(
            A, B, D,
            transposeA: A_trans, transposeB: B_trans, transposeD: D_trans,
            fusedBias: useBias)
          backend.markLastCommand()
          _ = backend.synchronize()
        }
      } else {
        var minTime: Double = .infinity
        for _ in 0..<trials {
          backend.markFirstCommand()
          for _ in 0..<iterations {
            C.matmul(
              A, B, D,
              transposeA: A_trans, transposeB: B_trans, transposeD: D_trans,
              fusedBias: useBias)
          }
          backend.markLastCommand()
          minTime = min(minTime, backend.synchronize())
        }

        if reportResults {
          var floatOps = 2 * M * N * K * iterations
          if let batchSize {
            floatOps *= batchSize
          }
          let flops = Double(floatOps) / minTime
          self.flops[currentConfig!]!.append(flops)
        }
      }

      if isInitial {
        let mps_A = Tensor(copying: py_A, backend: .mps)
        let mps_B = Tensor(copying: py_B, backend: .mps)
        var mps_C = Tensor<Inner>(zerosLike: shapeC, backend: .mps)

        var mps_D: Tensor<Inner>?
        if let py_D {
          mps_D = Tensor(copying: py_D, backend: .mps)
        }
        _ExecutionContext.withDefaultBackend(.mps) {
          _ExecutionContext.profileCommands {
            mps_C.matmul(
              mps_A, mps_B, mps_D,
              transposeA: A_trans, transposeB: B_trans, transposeD: D_trans,
              fusedBias: useBias)
          }
        }

        let params = EuclideanDistanceParameters(
          matrixK: K, batchSize: batchSize)
        if !C.isApproximatelyEqual(to: mps_C, parameters: params) {
//          MPL_showComparison(
//            actual: C, actualName: self.currentConfig!.name,
//            expected: mps_C, expectedName: "MPS", parameters: params)
          let distance = C.euclideanDistance(to: mps_C)
          fatalError("Tensors did not match. Euclidean distance: \(distance)")
        }

        mps_A.buffer.release()
        mps_B.buffer.release()
        mps_C.buffer.release()
        mps_D?.buffer.release()
      }
    }

    // Run the last matrix in the batch once to warm up, then actually start
    // benchmarking.
    innerLoop(size: sizes.upperBound - 1, reportResults: false)
    for size in sizes {
      innerLoop(size: size, reportResults: true)
    }
  }

  mutating func profile(
    granularity: Int, trialsExtension: Int, logProgress: Bool,
    A_trans: Bool, B_trans: Bool, D_trans: Bool,
    batchSize: Int?, useBias: Bool
  ) {
    let reportGranularity = 16
    var start = self.sizes.lowerBound
    while start < self.sizes.upperBound {
      var end: Int
      if start + reportGranularity + 2 >= self.sizes.upperBound {
        end = self.sizes.upperBound
      } else {
        end = start + reportGranularity
      }

      let sectionSizes = start..<end
      for config in Config.fastConfigs {
        autoreleasepool {
          prepare(config: config)
          _profile(
            sizes: sectionSizes, granularity: granularity,
            trialsExtension: trialsExtension, isInitial: true,
            A_trans: A_trans, B_trans: B_trans, D_trans: D_trans,
            batchSize: batchSize, useBias: useBias)
        }

        autoreleasepool {
          _profile(
            sizes: sectionSizes, granularity: granularity,
            trialsExtension: trialsExtension, isInitial: false,
            A_trans: A_trans, B_trans: B_trans, D_trans: D_trans,
            batchSize: batchSize, useBias: useBias)
        }
        cleanup(config: config)
      }

      if logProgress {
        for size in sectionSizes {
          if size % granularity != 0 {
            continue
          }
          var message = "\(size)x\(size)x\(size)x\(T.shortDescription)"

          if let batchSize {
            message = "\(batchSize)x\(message)"
          }
          for config in Config.fastConfigs {
            let index = size - sizes.lowerBound
            let gflops = flops[config]![index] / 1e9
            message += " - \(config.name)"
            message += " \(Int(gflops))"
          }
          print(message)
        }
      }

      if start + reportGranularity + 2 >= self.sizes.upperBound {
        break
      } else {
        start += reportGranularity
      }
    }
  }
}