//
//  RuleEditorView.swift
//  CC Shortcut
//

import SwiftUI

struct RuleEditorView: View {
    @EnvironmentObject private var store: RuleStore
    let ruleID: ShortcutRule.ID
    var onCancel: () -> Void = {}

    @State private var triggerKeyCode: Int?
    @State private var triggerModifiers: Modifiers = []
    @State private var targetKeyCode: Int?
    @State private var targetModifiers: Modifiers = []
    @State private var label: String = ""

    @State private var showDuplicateAlert = false
    @State private var didSaveFlash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 내가 누를 키 (이전 "트리거 단축키")
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("내가 누를 키", systemImage: "target")
                    Text("키보드에서 직접 누를 키 조합입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    KeyCaptureField(
                        title: "클릭하고 키 조합을 입력",
                        keyCode: $triggerKeyCode,
                        modifiers: $triggerModifiers
                    )
                }

                HStack {
                    Spacer()
                    Image(systemName: "arrow.down")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // 실제로 작동할 키 (이전 "원본 단축키")
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("실제로 작동할 키", systemImage: "bolt.fill")
                    Text("위 키를 누르면 활성 앱에 이 키가 전달됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    KeyCaptureField(
                        title: "클릭하고 키 조합을 입력",
                        keyCode: $targetKeyCode,
                        modifiers: $targetModifiers
                    )
                }

                // 메모
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("메모", systemImage: "text.alignleft")
                    TextField("예: 빠른 탭 전환", text: $label)
                        .textFieldStyle(.roundedBorder)
                }

                if !triggerIsValid && triggerKeyCode != nil {
                    Label(
                        "\"내가 누를 키\"에는 모디파이어(⌘ ⌃ ⌥ ⇧)가 하나 이상 필요합니다.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    if didSaveFlash {
                        Label("저장됨", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Spacer()
                    Button("취소", action: cancel)
                        .keyboardShortcut(.cancelAction)
                    Button("되돌리기") { load() }
                        .keyboardShortcut("r", modifiers: [.command])
                        .disabled(!hasChanges)
                    Button("저장", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { load() }
        .onChange(of: ruleID) { _, _ in load() }
        .alert("이미 동일한 키 조합이 등록되어 있습니다", isPresented: $showDuplicateAlert) {
            Button("확인", role: .cancel) { }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private var triggerIsValid: Bool {
        triggerKeyCode != nil && !triggerModifiers.isEmpty
    }

    private var canSave: Bool {
        triggerIsValid && targetKeyCode != nil && hasChanges
    }

    private var hasChanges: Bool {
        guard let original = store.rule(for: ruleID) else { return false }
        return original.triggerKeyCode != triggerKeyCode
            || original.triggerModifiers != triggerModifiers
            || original.targetKeyCode != targetKeyCode
            || original.targetModifiers != targetModifiers
            || original.label != label
    }

    private func cancel() {
        // 새로 추가한 빈 규칙이면 같이 삭제 — 안 그러면 리스트에 '— → —'
        // 빈 항목이 남음. 사용자가 한 번도 키를 안 입력한 경우만 해당.
        if let r = store.rule(for: ruleID),
           r.triggerKeyCode == nil && r.targetKeyCode == nil && r.label.isEmpty {
            NSLog("[CCShortcut] cancel — deleting unfilled rule \(ruleID)")
            store.delete(id: ruleID)
        } else {
            NSLog("[CCShortcut] cancel — discarding unsaved changes for \(ruleID)")
        }
        onCancel()
    }

    private func load() {
        guard let r = store.rule(for: ruleID) else { return }
        triggerKeyCode = r.triggerKeyCode
        triggerModifiers = r.triggerModifiers
        targetKeyCode = r.targetKeyCode
        targetModifiers = r.targetModifiers
        label = r.label
        didSaveFlash = false
    }

    private func save() {
        NSLog("[CCShortcut] RuleEditorView.save() called — triggerKeyCode=\(triggerKeyCode?.description ?? "nil") triggerMods=\(triggerModifiers.rawValue) targetKeyCode=\(targetKeyCode?.description ?? "nil") targetMods=\(targetModifiers.rawValue) hasChanges=\(hasChanges) canSave=\(canSave)")

        guard let tk = triggerKeyCode, let tgt = targetKeyCode else {
            NSLog("[CCShortcut]   save aborted: trigger or target keyCode is nil")
            return
        }

        if store.isDuplicate(
            triggerKeyCode: tk,
            triggerModifiers: triggerModifiers,
            excluding: ruleID
        ) {
            NSLog("[CCShortcut]   save aborted: duplicate trigger")
            showDuplicateAlert = true
            return
        }

        let updated = ShortcutRule(
            id: ruleID,
            triggerKeyCode: tk,
            triggerModifiers: triggerModifiers,
            targetKeyCode: tgt,
            targetModifiers: targetModifiers,
            label: label
        )
        store.update(updated)

        withAnimation { didSaveFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { didSaveFlash = false }
        }
    }
}
