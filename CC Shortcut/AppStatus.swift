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

    /// Reference to the event tap so capture mode UI can install its callback
    /// without going through NSApp.delegate (which can be unreliable on some
    /// SwiftUI launch paths).
    var eventTap: EventTapManager?

    /// Closures wired up by AppDelegate so SwiftUI views can trigger
    /// backup/restore without going through NSApp.delegate.
    var exportAction: () -> Void = {
        NSLog("[CCShortcut] exportAction not wired up — AppStatus.exportAction is the default no-op")
    }
    var importAction: () -> Void = {
        NSLog("[CCShortcut] importAction not wired up — AppStatus.importAction is the default no-op")
    }
}
