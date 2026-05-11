//
//  EventTapManager.swift
//  CC Shortcut
//
//  Captures global keyboard events via CGEventTap and remaps them based on
//  the user's rules.
//

import Foundation
import CoreGraphics
import AppKit

nonisolated final class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var rules: [ShortcutRule] = []
    private var captureCallback: (@Sendable (Int, Modifiers) -> Void)?
    private let lock = NSLock()

    /// Tag stamped on events we synthesize, so we can recognize and skip them
    /// when they re-enter our callback (no infinite loop).
    private static let injectedTag: Int64 = 0x4343_5343_5343 // "CCSCSC"

    func updateRules(_ rules: [ShortcutRule]) {
        lock.lock()
        self.rules = rules.filter { $0.isComplete }
        let count = self.rules.count
        lock.unlock()
        NSLog("[CCShortcut] updateRules: \(count) active rule(s)")
    }

    /// Install a one-shot key-capture callback. While set, all key events are
    /// consumed (not remapped, not delivered to other apps) and the first
    /// keyDown is forwarded to the callback. Set to nil to leave capture mode.
    func setCaptureCallback(_ callback: (@Sendable (Int, Modifiers) -> Void)?) {
        lock.lock()
        captureCallback = callback
        lock.unlock()
        NSLog("[CCShortcut] setCaptureCallback: \(callback == nil ? "cleared" : "installed")")
    }

    private func currentRules() -> [ShortcutRule] {
        lock.lock()
        defer { lock.unlock() }
        return rules
    }

    private func currentCaptureCallback() -> (@Sendable (Int, Modifiers) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return captureCallback
    }

    var isActive: Bool { eventTap != nil }

    func start() {
        NSLog("[CCShortcut] EventTapManager.start() called")

        guard eventTap == nil else {
            NSLog("[CCShortcut]   tap already exists — skipping")
            return
        }

        let trusted = AXIsProcessTrusted()
        NSLog("[CCShortcut]   AXIsProcessTrusted() = \(trusted)")

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            NSLog("[CCShortcut]   ❌ CGEvent.tapCreate returned nil — Accessibility permission not effective for this process (likely signing/TCC mismatch)")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[CCShortcut]   ✓ event tap created at .cgSessionEventTap (head insert) and enabled")
    }

    func stop() {
        NSLog("[CCShortcut] EventTapManager.stop() called")
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            NSLog("[CCShortcut] ⚠️ tap disabled by TIMEOUT — re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            NSLog("[CCShortcut] ⚠️ tap disabled by USER INPUT — re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // Skip events we synthesized ourselves (otherwise infinite loop).
        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedTag {
            let kc = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let mds = Modifiers(cgFlags: event.flags)
            NSLog("[CCShortcut]   (our injected event keyCode=\(kc) mods='\(mds.symbolString)' raw=\(mds.rawValue) — pass through)")
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = Modifiers(cgFlags: event.flags)
        let typeStr = type == .keyDown ? "DOWN" : "UP "

        NSLog("[CCShortcut] \(typeStr) keyCode=\(keyCode) mods='\(mods.symbolString)' (raw=\(mods.rawValue))")

        // Capture mode: consume the event and (on keyDown) forward to callback.
        if let capture = currentCaptureCallback() {
            NSLog("[CCShortcut]   → capture mode, forwarding")
            if type == .keyDown {
                capture(keyCode, mods)
            }
            return nil
        }

        // Remap: find a matching rule.
        let rules = currentRules()
        guard let rule = rules.first(where: {
            $0.triggerKeyCode == keyCode && $0.triggerModifiers == mods
        }), let targetKeyCode = rule.targetKeyCode else {
            NSLog("[CCShortcut]   → no rule match among \(rules.count) rules — pass through")
            return Unmanaged.passUnretained(event)
        }

        NSLog("[CCShortcut]   ★ MATCH! trigger='\(rule.triggerModifiers.symbolString)\(rule.triggerKeyCode ?? -1)' → target='\(rule.targetModifiers.symbolString)\(targetKeyCode)'")

        // Consume the trigger and post a fresh event with the target keycode
        // + flags.
        let source = CGEventSource(stateID: .hidSystemState)
        if let newEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(targetKeyCode),
            keyDown: type == .keyDown
        ) {
            newEvent.flags = rule.targetModifiers.cgFlags
            newEvent.setIntegerValueField(.eventSourceUserData, value: Self.injectedTag)
            // Post at HID level so the event flows through the full chain
            // like a real keystroke, and arrives at the active app with the
            // flags we specified (instead of being "corrected" downstream).
            newEvent.post(tap: .cghidEventTap)
            NSLog("[CCShortcut]   ✓ posted synthesized \(typeStr) event keyCode=\(targetKeyCode) flags='\(rule.targetModifiers.symbolString)' via .cghidEventTap")
        } else {
            NSLog("[CCShortcut]   ❌ CGEvent creation failed for targetKeyCode=\(targetKeyCode)")
        }

        return nil  // consume original
    }
}
