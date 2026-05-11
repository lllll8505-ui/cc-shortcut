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
    private let lock = NSLock()

    func updateRules(_ rules: [ShortcutRule]) {
        lock.lock()
        self.rules = rules.filter { $0.isComplete }
        lock.unlock()
    }

    private func currentRules() -> [ShortcutRule] {
        lock.lock()
        defer { lock.unlock() }
        return rules
    }

    var isActive: Bool { eventTap != nil }

    func start() {
        guard eventTap == nil else { return }

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

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = Modifiers(cgFlags: event.flags)

        guard let rule = currentRules().first(where: {
            $0.triggerKeyCode == keyCode && $0.triggerModifiers == mods
        }), let targetKeyCode = rule.targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Preserve non-mapped flags (e.g. CapsLock, Fn) by clearing only the
        // four primary modifier bits and OR-ing in the target's modifiers.
        let primaryMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        var newFlags = event.flags
        newFlags.remove(primaryMask)
        newFlags.insert(rule.targetModifiers.cgFlags)

        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(targetKeyCode))
        event.flags = newFlags

        return Unmanaged.passUnretained(event)
    }
}
