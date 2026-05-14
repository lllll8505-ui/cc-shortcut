//
//  MoveToApplications.swift
//  CC Shortcut
//

import Foundation

enum MoveToApplications {

    // 자동이동이 방금 완료됐음을 알리는 플래그 파일
    private static let movedFlag = "/tmp/ccshortcut-moved"

    static func moveIfNeeded() {
        let bundlePath = Bundle.main.bundlePath
        let appsDir    = "/Applications"

        // /Applications에서 실행 중 → 플래그가 있을 때만 원본 삭제
        if bundlePath.hasPrefix(appsDir) {
            removeOutsideCopiesIfFlagged()
            return
        }

        // Xcode / DerivedData 빌드 환경에서는 건너뜀
        guard !bundlePath.contains("DerivedData"),
              !bundlePath.contains("Xcode") else { return }

        let appName     = (bundlePath as NSString).lastPathComponent
        let destination = (appsDir as NSString).appendingPathComponent(appName)

        // 1) 기존 /Applications 버전 제거
        run("/bin/rm", ["-rf", destination])

        // 2) ditto 복사 (실행 중에도 안전, 심볼릭 링크·메타데이터 보존)
        guard run("/usr/bin/ditto", [bundlePath, destination]) == 0 else {
            NSLog("[CCShortcut] ditto 실패")
            return
        }

        // 3) /Applications 복사본의 quarantine 제거 → "손상됨" 오류 방지
        run("/usr/bin/xattr", ["-rd", "com.apple.quarantine", destination])

        // 4) 자동이동 플래그 기록
        try? "moved".write(toFile: movedFlag, atomically: true, encoding: .utf8)

        // 5) /Applications 버전 실행 후 즉시 종료
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && /usr/bin/open \"\(destination)\""]
        try? task.run()
        exit(0)
    }

    // 플래그가 있을 때만 Downloads·Desktop의 동명 앱 삭제
    // 삭제 성공 후 플래그 제거 → 실패 시 다음 실행에서 재시도
    private static func removeOutsideCopiesIfFlagged() {
        guard FileManager.default.fileExists(atPath: movedFlag) else { return }

        let appName    = (Bundle.main.bundlePath as NSString).lastPathComponent
        let home       = NSHomeDirectory()
        let searchDirs = ["\(home)/Downloads", "\(home)/Desktop"]
        var allRemoved = true

        for dir in searchDirs {
            let candidate = (dir as NSString).appendingPathComponent(appName)
            guard candidate != Bundle.main.bundlePath,
                  FileManager.default.fileExists(atPath: candidate) else { continue }
            run("/usr/bin/chflags", ["-R", "nouchg", candidate])
            do {
                try FileManager.default.removeItem(atPath: candidate)
                NSLog("[CCShortcut] 외부 복사본 삭제: \(candidate)")
            } catch {
                NSLog("[CCShortcut] 삭제 실패: \(candidate) — \(error)")
                allRemoved = false
            }
        }

        // 모두 성공했을 때만 플래그 제거 (실패 시 다음 실행에서 재시도)
        if allRemoved {
            try? FileManager.default.removeItem(atPath: movedFlag)
        }
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
