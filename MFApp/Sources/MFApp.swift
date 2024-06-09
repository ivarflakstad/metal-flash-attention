//
//  MFAApp.swift
//  MFA
//
//  Created by Ivar Arning Flakstad on 02/05/2024.
//

import SwiftUI
import MFALib

@main
struct MFApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    #if os(macOS)
    .windowStyle(HiddenTitleBarWindowStyle())
    #endif
  }
}
