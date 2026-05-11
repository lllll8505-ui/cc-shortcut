//
//  PermissionView.swift
//  CC Shortcut
//

import SwiftUI

struct PermissionView: View {
    @EnvironmentObject private var permission: AccessibilityPermission

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "lock.shield")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("손쉬운 사용 권한이 필요합니다")
                    .font(.title2.bold())
                Text("CC Shortcut가 전역 키보드 단축키를 가로채려면\n시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서\n이 앱을 허용해 주세요.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("시스템 설정 열기") {
                permission.request()  // 앱을 권한 목록에 등록
                permission.openSystemSettings()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.top, 4)

            Text("토글을 켜면 잠시 후 자동으로 활성화됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
