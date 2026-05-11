//
//  EventTapManager.swift
//  CC Shortcut
//
//  Captures global keyboard events via CGEventTap and remaps them based on
//  the user's rules. Runs on the main thread (event tap callbacks happen on
//  the main run loop).
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
        lock.unlock()
    }

    /// Install a one-shot key-capture callback. While set, all key events are
    /// consumed (not remapped, not delivered to other apps) and the first
    /// keyDown is forwarded to the callback. Set to nil to leave capture mode.
    func setCaptureCallback(_ callback: (@Sendable (Int, Modifiers) -> Void)?) {
        lock.lock()
        captureCallback = callback
        lock.unlock()
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
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // Session-level tap (works with just Accessibility, same level BTT
        // uses). Inserted at head of chain so we precede other taps and
        // most system shortcut handlers.
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
            NSLog("CC Shortcut: failed to create event tap (permission denied?)")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
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
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = Modifiers(cgFlags: event.flags)

        // Capture mode: consume the event and (on keyDown) forward to callback.
        if let capture = currentCaptureCallback() {
            if type == .keyDown {
                capture(keyCode, mods)
            }
            return nil
        }

        // Remap: find a matching rule.
        guard let rule = currentRules().first(where: {
            $0.triggerKeyCode == keyCode && $0.triggerModifiers == mods
        }), let targetKeyCode = rule.targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Consume the trigger and post a fresh event with the target keycode
        // + flags. This is more reliable than mutating the event in-place
        // (which doesn't always propagate to AppKit shortcut matching).
        let source = CGEventSource(stateID: .hidSystemState)
        if let newEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(targetKeyCode),
            keyDown: type == .keyDown
        ) {
            newEvent.flags = rule.targetModifiers.cgFlags
            newEvent.setIntegerValueField(.eventSourceUserData, value: Self.injectedTag)
            // Post at session level so we bypass any HID-level taps from
            // other apps (LinearMouse, Logi Options+) — the synthesized
            // event goes directly to the active app.
            newEvent.post(tap: .cgSessionEventTap)
        }

        return nil  // consume original
    }
}
