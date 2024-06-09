//
//  ContentView.swift
//  MFA
//
//  Created by Ivar Arning Flakstad on 02/05/2024.
//

import SwiftUI
import Charts
import MFALib

enum Operation: String, CaseIterable, Identifiable {
  var id: Self {
    return self
  }
  case attention, gemm, correctness
}

enum Datatype: String, CaseIterable, Identifiable {
  var id: Self {
    return self
  }
  case f32, f16, bf16
}

struct OpRow: View {
  var name: String
  var body: some View {
    HStack {
      Text(name)
    }
  }
}


struct Result: Identifiable {
  let name: String
  let size: Int
  let gflops: Double
  
  var id: String { name }
}

/// A data series for the lines.
struct Series: Identifiable {
    let name: String
    let results: [Result]
    var id: String { name }
}

struct OpDetail: View {
  let datatypes = Datatype.allCases
  let symbolSize: CGFloat = 100
  let lineWidth: CGFloat = 3
  
  enum RunningState: String, CaseIterable, Identifiable {
    var id: Self {
      return self
    }
    case idle, running, done
  }
  
  var op: Operation
  
  let colorMap: [String: Color] = [
    "MPS": .purple,
    "MFA 48x48": .blue,
    "MFA 32x32": .green
  ]
  
  @State private var isDragging = false
  @State private var magnifyBy = 1.0
  @State private var title = "Select a datatype"
  @State private var state: RunningState = .idle
  @State private var series: [Series] = []
  @State var rawSelected: Int? = nil
  
  var selected: [Series]? {
      if let rawSelected {
        return series
      }
      return nil
  }
  
  var body: some View {
    
    switch state {
    case .idle:
      NavigationView {
        List(datatypes) { dtype in
          Button(dtype.rawValue) {
            self.state = .running
            self.title = "Running"
            DispatchQueue.global(qos: .background).async {
              self.series = run(op: op, dtype: dtype)
              DispatchQueue.main.async {
                self.state = .done
                self.title = "Select a datatype"
              }
            }
          }
        }
        .navigationTitle("Operations")
      }
    case .running:
      ProgressView()
    case .done:
      Chart(series) { series in
        ForEach(series.extracts, id: \.name) { element in
          LineMark(
            x: .value("Date", element.size),
            y: .value("Sales", element.gflops)
          )
          //          .interpolationMethod(.cardinal)
          .foregroundStyle(by: .value("Name", element.name))
          .symbol(by: .value("Name", element.name))
        }
        .interpolationMethod(.catmullRom)
        .lineStyle(StrokeStyle(lineWidth: lineWidth))
        .symbolSize(symbolSize)
      }
      .chartScrollableAxes([.horizontal, .vertical])
      .chartForegroundStyleScale { colorMap[$0]! }
      .chartSymbolScale([
        "MFA 32x32": Circle().strokeBorder(lineWidth: 2),
        "MFA 48x48": Circle().strokeBorder(lineWidth: 2),
        "MPS": Square().strokeBorder(lineWidth: 2)
      ])
      .chartXAxis(.automatic)
      .chartYAxis(.automatic)
      .chartLegend(.automatic)
    }
  }
  @ViewBuilder
  var valueSelectionPopover: some View {
    if let selectedDate,
       let salesPerCity = salesPerCity(on: selectedDate) {
      VStack(alignment: .leading) {
        Text("Average on \(selectedDate, format: .dateTime.weekday(.wide))s")
          .font(preTitleFont)
          .foregroundStyle(.secondary)
          .fixedSize()
        HStack(spacing: 20) {
          ForEach(salesPerCity) { salesInfo in
            VStack(alignment: .leading, spacing: 1) {
              HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(salesInfo.count, format: .number)")
                  .font(titleFont)
                  .foregroundColor(colorPerCity[salesInfo.city])
                  .blendMode(colorScheme == .light ? .plusDarker : .normal)
                
                Text("sales")
                  .font(preTitleFont)
                  .foregroundStyle(.secondary)
              }
              HStack(spacing: 6) {
                if salesInfo.city == "San Francisco" {
                  legendCircle
                } else {
                  legendSquare
                }
                Text("\(salesInfo.city)")
                  .font(labelFont)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .padding(6)
      .background {
        RoundedRectangle(cornerRadius: 4)
          .foregroundStyle(Color.gray.opacity(0.12))
      }
    } else {
      EmptyView()
    }
  }
}


/// A square symbol for charts.
struct Square: ChartSymbolShape, InsettableShape {
    let inset: CGFloat

    init(inset: CGFloat = 0) {
        self.inset = inset
    }

    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 1
        let minDimension = min(rect.width, rect.height)
        return Path(
            roundedRect: .init(x: rect.midX - minDimension / 2, y: rect.midY - minDimension / 2, width: minDimension, height: minDimension),
            cornerRadius: cornerRadius
        )
    }

    func inset(by amount: CGFloat) -> Square {
        Square(inset: inset + amount)
    }

    var perceptualUnitRect: CGRect {
        // The width of the unit rectangle (square). Adjust this to
        // size the diamond symbol so it perceptually matches with
        // the circle.
        let scaleAdjustment: CGFloat = 0.75
        return CGRect(x: 0.5 - scaleAdjustment / 2, y: 0.5 - scaleAdjustment / 2, width: scaleAdjustment, height: scaleAdjustment)
    }
}


func run(op: Operation, dtype: Datatype) -> [Series] {
  processBenchResults(results: try! runBench(op:op, dtype:dtype))
}

func processBenchResults(results: [String : [Extraction]]) -> [Series] {
  results.flatMap { name, extractions in
    extractions.compactMap { extraction in
      var extracts: [(Int, Double, String)] = []
      zip(extraction.sizeArray, extraction.gflopsArray).forEach { (s, g) in
        extracts.append((s, g, extraction.title))
      }
      return Series(
        name: name,
        extracts: extracts
      );
    }
  }
}

func runBench(op: Operation, dtype: Datatype) throws -> [String : [Extraction]] {
  return switch op {
  case .attention:
    switch dtype {
    case .f32:
      TestCaseRunner.runTests(testCases: [AttentionPerfTests<Float>()], speed: TestSpeed.veryLong)
    case .f16:
      TestCaseRunner.runTests(testCases: [AttentionPerfTests<Float16>()], speed: TestSpeed.veryLong)
    case .bf16:
      TestCaseRunner.runTests(testCases: [AttentionPerfTests<BFloat>()], speed: TestSpeed.veryLong)
    }
  case .gemm:
    switch dtype {
    case .f32:
      TestCaseRunner.runTests(testCases: [GEMMPerfTests<Float>()], speed: TestSpeed.veryLong)
    case .f16:
      TestCaseRunner.runTests(testCases: [GEMMPerfTests<Float16>()], speed: TestSpeed.veryLong)
    case .bf16:
      TestCaseRunner.runTests(testCases: [GEMMPerfTests<BFloat>()], speed: TestSpeed.veryLong)
    }
  case .correctness:
    [:]
  }
}

struct ContentView: View {
  let operations = Operation.allCases
  
  @State private var selection: Operation = .attention
  
  var body: some View {
    TabView(selection: $selection) {
      ForEach(operations) { op in
        OpDetail(op: op)
          .tabItem {
            Label(op.rawValue, systemImage: "star")
          }
          .tag(op)
      }
    }
    //      List(operations) { op in
    //        NavigationLink (destination: OpDetail(op: op)) {
    //          OpRow(name: op.rawValue.capitalized)
    //        }
    //      }
    //      .navigationTitle("Operations")
    //      .navigationBarBackButtonHidden()
  }
}
#Preview {
  ContentView()
}
