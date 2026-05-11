//
//  AccessibilityPermission.swift
//  CC Shortcut
//

import Foundation
import AppKit
import ApplicationServices
import Combine

@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isTrusted: Bool

    private var monitorTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    init() {
        self.isTrusted = AXIsProcessTrusted()
        startMonitoring()
        observeAppActivation()
    }

    deinit {
        monitorTask?.cancel()
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func startMonitoring() {
        // Poll every 0.5s — TCC has no notification API, so polling is the
        // only way to learn that the user toggled Accessibility on.
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.refresh()
            }
        }
    }

    private func observeAppActivation() {
        // Immediately re-check when the user comes back to the app after
        // toggling permission in System Settings.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let current = AXIsProcessTrusted()
        if current != isTrusted {
            isTrusted = current
        }
    }

    func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        if result != isTrusted {
            isTrusted = result
        }
    }

    func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
