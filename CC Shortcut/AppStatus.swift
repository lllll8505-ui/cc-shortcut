//
//  AppStatus.swift
//  CC Shortcut
//
//  Exposes runtime state (whether the global event tap is alive) to SwiftUI
//  so the user can verify the app is actually intercepting keystrokes.
//

import Foundation
import Combine

@MainActor
final class AppStatus: ObservableObject {
    @Published var isEventTapActive: Bool = false
}
