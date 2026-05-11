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
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Image(systemName: "lock.shield")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("손쉬운 사용 권한이 필요합니다")
                    .font(.title2.bold())

                if didOpenSettings {
                    Text("시스템 설정 → 손쉬운 사용에서\nCC Shortcut을 켜셨나요?\n아래 버튼으로 앱을 다시 시작하면 적용됩니다.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("CC Shortcut가 전역 키보드 단축키를 가로채려면\n시스템 설정에서 손쉬운 사용 권한을 허용해 주세요.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 10) {
                if didOpenSettings {
                    Button("권한 허용 완료 — 앱 다시 시작") {
                        relaunchApp()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Button("시스템 설정 다시 열기") {
                        permission.openSystemSettings()
                    }
                    .controlSize(.regular)
                } else {
                    Button("시스템 설정 열기") {
                        permission.request()  // 앱을 권한 목록에 등록
                        permission.openSystemSettings()
                        didOpenSettings = true
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
