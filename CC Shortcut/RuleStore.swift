//
//  RuleStore.swift
//  CC Shortcut
//

import Foundation
import Combine

@MainActor
final class RuleStore: ObservableObject {
    static let maxRules = 200

    @Published private(set) var rules: [ShortcutRule] = []

    private let storageURL: URL

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = support.appendingPathComponent("CC Shortcut", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("rules.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([ShortcutRule].self, from: data) {
            self.rules = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(rules) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    @discardableResult
    func add() -> ShortcutRule? {
        add(ShortcutRule())
    }

    @discardableResult
    func add(_ rule: ShortcutRule) -> ShortcutRule? {
        guard rules.count < Self.maxRules else { return nil }
        rules.append(rule)
        persist()
        return rule
    }

    func update(_ rule: ShortcutRule) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx] = rule
        persist()
    }

    func delete(id: ShortcutRule.ID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    func rule(for id: ShortcutRule.ID) -> ShortcutRule? {
        rules.first { $0.id == id }
    }

    func isDuplicate(
        triggerKeyCode: Int,
        triggerModifiers: Modifiers,
        excluding id: ShortcutRule.ID?
    ) -> Bool {
        rules.contains { r in
            r.id != id &&
            r.triggerKeyCode == triggerKeyCode &&
            r.triggerModifiers == triggerModifiers
        }
    }
}
