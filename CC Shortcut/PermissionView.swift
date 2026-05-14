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
                    Text("시스템 설정 → 손쉬운 사용에서\nCC Shortcut을 켜셨다면\n아래 버튼으로 앱을 다시 시작해 주세요.")
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
        // 구 인스턴스를 먼저 종료한 뒤 새 인스턴스를 열어야
        // applicationDidFinishLaunching의 중복 인스턴스 체크와
        // 타이밍 경쟁이 생기지 않는다.
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && /usr/bin/open -n \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
