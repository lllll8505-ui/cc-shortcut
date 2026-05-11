//
//  RuleListView.swift
//  CC Shortcut
//

import SwiftUI

struct RuleListView: View {
    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var status: AppStatus
    @Binding var selection: ShortcutRule.ID?

    var body: some View {
        VStack(spacing: 0) {
            // EventTap status banner — green = remap running, red = not.
            HStack(spacing: 6) {
                Circle()
                    .fill(status.isEventTapActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(status.isEventTapActive ? "리매핑 활성" : "리매핑 비활성")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List(selection: $selection) {
                ForEach(store.rules) { rule in
                    RuleRow(rule: rule)
                        .tag(rule.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(id: rule.id)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))

            Divider()

            HStack(spacing: 6) {
                Button(action: addRule) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(store.rules.count >= RuleStore.maxRules)
                .help("규칙 추가")

                Button(action: deleteSelected) {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help("선택한 규칙 삭제")

                Divider()
                    .frame(height: 16)

                Button {
                    (NSApp.delegate as? AppDelegate)?.exportRulesToFile()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("규칙 백업 저장…")
                .disabled(store.rules.isEmpty)

                Button {
                    (NSApp.delegate as? AppDelegate)?.importRulesFromFile()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("백업에서 규칙 복원…")

                Spacer()

                Text("\(store.rules.count) / \(RuleStore.maxRules)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func addRule() {
        if let added = store.add() {
            selection = added.id
        }
    }

    private func deleteSelected() {
        NSLog("[CCShortcut] RuleListView.deleteSelected() called — selection=\(selection?.uuidString ?? "nil")")
        guard let id = selection else {
            NSLog("[CCShortcut]   delete aborted: no selection")
            return
        }
        delete(id: id)
    }

    /// Delete by explicit id (used by context menu and - button).
    private func delete(id: ShortcutRule.ID) {
        let rules = store.rules
        let removingIndex = rules.firstIndex(where: { $0.id == id })
        store.delete(id: id)

        if selection == id {
            if let idx = removingIndex {
                let remaining = store.rules
                if remaining.isEmpty {
                    selection = nil
                } else {
                    let next = min(idx, remaining.count - 1)
                    selection = remaining[next].id
                }
            } else {
                selection = nil
            }
        }
    }
}

private struct RuleRow: View {
    let rule: ShortcutRule

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ShortcutChip(keyCode: rule.triggerKeyCode, modifiers: rule.triggerModifiers)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ShortcutChip(keyCode: rule.targetKeyCode, modifiers: rule.targetModifiers)
                }
                if !rule.label.isEmpty {
                    Text(rule.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutChip: View {
    let keyCode: Int?
    let modifiers: Modifiers

    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(keyCode == nil ? .secondary : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            )
    }

    private var text: String {
        guard let keyCode else { return "—" }
        return modifiers.symbolString + KeyCodeMap.displayName(for: keyCode)
    }
}
