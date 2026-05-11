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

    init() {
        self.isTrusted = AXIsProcessTrusted()
        startMonitoring()
    }

    deinit {
        monitorTask?.cancel()
    }

    private func startMonitoring() {
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let current = AXIsProcessTrusted()
                if current != self.isTrusted {
                    self.isTrusted = current
                }
            }
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
