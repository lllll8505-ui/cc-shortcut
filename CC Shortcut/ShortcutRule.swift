//
//  ShortcutRule.swift
//  CC Shortcut
//

import Foundation
import AppKit
import CoreGraphics

nonisolated struct Modifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt64

    static let command  = Modifiers(rawValue: 1 << 0)
    static let shift    = Modifiers(rawValue: 1 << 1)
    static let option   = Modifiers(rawValue: 1 << 2)
    static let control  = Modifiers(rawValue: 1 << 3)

    init(rawValue: UInt64) { self.rawValue = rawValue }

    init(nsFlags: NSEvent.ModifierFlags) {
        var m = Modifiers()
        if nsFlags.contains(.command) { m.insert(.command) }
        if nsFlags.contains(.shift)   { m.insert(.shift) }
        if nsFlags.contains(.option)  { m.insert(.option) }
        if nsFlags.contains(.control) { m.insert(.control) }
        self = m
    }

    init(cgFlags: CGEventFlags) {
        var m = Modifiers()
        if cgFlags.contains(.maskCommand)   { m.insert(.command) }
        if cgFlags.contains(.maskShift)     { m.insert(.shift) }
        if cgFlags.contains(.maskAlternate) { m.insert(.option) }
        if cgFlags.contains(.maskControl)   { m.insert(.control) }
        self = m
    }

    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.command) { f.insert(.maskCommand) }
        if contains(.shift)   { f.insert(.maskShift) }
        if contains(.option)  { f.insert(.maskAlternate) }
        if contains(.control) { f.insert(.maskControl) }
        return f
    }

    var symbolString: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    var isEmpty: Bool { rawValue == 0 }
}

extension Modifiers: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt64.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct ShortcutRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var triggerKeyCode: Int?
    var triggerModifiers: Modifiers = []
    var targetKeyCode: Int?
    var targetModifiers: Modifiers = []
    var label: String = ""

    var isComplete: Bool {
        triggerKeyCode != nil && targetKeyCode != nil
    }
}
