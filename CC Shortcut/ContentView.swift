//
//  ContentView.swift
//  CC Shortcut
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var permission: AccessibilityPermission

    @State private var selection: ShortcutRule.ID?

    var body: some View {
        Group {
            if !permission.isTrusted {
                PermissionView()
            } else {
                mainSplit
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var mainSplit: some View {
        HSplitView {
            RuleListView(selection: $selection)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            Group {
                if let id = selection, store.rule(for: id) != nil {
                    RuleEditorView(ruleID: id, onCancel: { selection = nil })
                        .id(id)  // 규칙이 바뀔 때 뷰를 완전히 새로 만들어 이전 데이터 잔류 방지
                } else {
                    EmptyEditorView()
                }
            }
            .frame(minWidth: 380)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("규칙을 선택하거나 + 버튼을 눌러 추가하세요")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
