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

    // MARK: - Backup / Restore

    /// Write all current rules to a JSON file the user picked.
    func exportRules(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: url, options: .atomic)
        NSLog("[CCShortcut] exportRules: \(rules.count) rule(s) → \(url.path)")
    }

    enum ImportMode {
        case replace   // 기존 규칙을 모두 지우고 백업으로 덮어쓰기
        case merge     // 기존 + 백업 합치기 (트리거 충돌 시 백업 측 무시)
    }

    /// Load rules from a backup file.
    @discardableResult
    func importRules(from url: URL, mode: ImportMode) throws -> Int {
        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder().decode([ShortcutRule].self, from: data)

        switch mode {
        case .replace:
            rules = Array(imported.prefix(Self.maxRules))
        case .merge:
            var merged = rules
            for var rule in imported {
                guard merged.count < Self.maxRules else { break }
                // Skip rules whose trigger already exists in current store.
                let conflict = merged.contains {
                    $0.triggerKeyCode == rule.triggerKeyCode &&
                    $0.triggerModifiers == rule.triggerModifiers &&
                    rule.triggerKeyCode != nil
                }
                if conflict { continue }
                // Refresh id so a re-import doesn't collide.
                rule.id = UUID()
                merged.append(rule)
            }
            rules = merged
        }
        persist()
        NSLog("[CCShortcut] importRules(mode=\(mode)): imported \(imported.count), store now has \(rules.count) rule(s)")
        return rules.count
    }
}
