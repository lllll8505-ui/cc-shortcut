//
//  PermissionView.swift
//  CC Shortcut
//

import SwiftUI
import AppKit

struct PermissionView: View {
    @EnvironmentObject private var permission: AccessibilityPermission
    @State private var didOpenSettings = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            Image(systemName: "lock.shield")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("CC Shortcut에 두 가지 권한이 필요합니다")
                    .font(.title2.bold())
                Text("아래 두 항목을 모두 켜고\n맨 아래 버튼으로 앱을 다시 시작해 주세요.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                permissionRow(
                    title: "손쉬운 사용",
                    subtitle: "키보드 이벤트 가로채기 및 변환",
                    granted: permission.isAccessibilityTrusted,
                    action: {
                        permission.requestAccessibility()
                        permission.openAccessibilitySettings()
                        didOpenSettings = true
                    }
                )
                permissionRow(
                    title: "입력 모니터링",
                    subtitle: "시스템 단축키(⌘⇧3 등)까지 가로채려면 필요",
                    granted: permission.isInputMonitoringTrusted,
                    action: {
                        permission.requestInputMonitoring()
                        permission.openInputMonitoringSettings()
                        didOpenSettings = true
                    }
                )
            }
            .frame(maxWidth: 480)

            if didOpenSettings {
                Button("권한 허용 완료 — 앱 다시 시작") {
                    relaunchApp()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(granted ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(granted ? "허용됨" : "설정 열기") {
                action()
            }
            .disabled(granted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
