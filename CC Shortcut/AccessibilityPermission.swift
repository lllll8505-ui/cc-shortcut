//
//  AccessibilityPermission.swift
//  CC Shortcut
//
//  Manages the two TCC permissions CC Shortcut needs:
//   1. Accessibility — to create a CGEventTap that can modify events
//   2. Input Monitoring — required for HID-level taps that catch system
//      shortcuts (⌘⇧3/4/5, Mission Control, …) before macOS processes them
//

import Foundation
import AppKit
import ApplicationServices
import IOKit.hid
import Combine

@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isAccessibilityTrusted: Bool
    @Published private(set) var isInputMonitoringTrusted: Bool

    var isFullyTrusted: Bool {
        isAccessibilityTrusted && isInputMonitoringTrusted
    }

    private var monitorTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    init() {
        self.isAccessibilityTrusted = AXIsProcessTrusted()
        self.isInputMonitoringTrusted =
            IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
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
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.refresh()
            }
        }
    }

    private func observeAppActivation() {
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
        let ax = AXIsProcessTrusted()
        let im = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if ax != isAccessibilityTrusted { isAccessibilityTrusted = ax }
        if im != isInputMonitoringTrusted { isInputMonitoringTrusted = im }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func requestInputMonitoring() {
        // Registers the app with TCC. The user still has to toggle the switch
        // in System Settings; this just makes the app appear in the list.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
