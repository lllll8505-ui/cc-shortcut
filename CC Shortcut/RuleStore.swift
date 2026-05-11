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
        guard rules.count < Self.maxRules else {
            NSLog("[CCShortcut] RuleStore.add rejected — at max capacity (\(Self.maxRules))")
            return nil
        }
        rules.append(rule)
        persist()
        NSLog("[CCShortcut] RuleStore.add OK — count=\(rules.count), id=\(rule.id)")
        return rule
    }

    func update(_ rule: ShortcutRule) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else {
            NSLog("[CCShortcut] RuleStore.update FAILED — id \(rule.id) not found")
            return
        }
        rules[idx] = rule
        persist()
        let trg = rule.triggerKeyCode.map(String.init) ?? "nil"
        let tgt = rule.targetKeyCode.map(String.init) ?? "nil"
        NSLog("[CCShortcut] RuleStore.update OK — id=\(rule.id) trigger='\(rule.triggerModifiers.symbolString)\(trg)' target='\(rule.targetModifiers.symbolString)\(tgt)'")
    }

    func delete(id: ShortcutRule.ID) {
        let beforeCount = rules.count
        rules.removeAll { $0.id == id }
        let afterCount = rules.count
        persist()
        NSLog("[CCShortcut] RuleStore.delete id=\(id) — count \(beforeCount) → \(afterCount)")
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
