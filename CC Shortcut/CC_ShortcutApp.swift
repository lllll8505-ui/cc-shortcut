//
//  CC_ShortcutApp.swift
//  CC Shortcut
//

import SwiftUI
import AppKit
import Combine
import Sparkle
import UniformTypeIdentifiers

@main
struct CC_ShortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        MoveToApplications.moveIfNeeded()
    }

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("업데이트 확인…") {
                        appDelegate.updaterController.checkForUpdates(nil)
                    }
                }
                CommandMenu("백업") {
                    Button("규칙 백업 저장…") {
                        appDelegate.exportRulesToFile()
                    }
                    .keyboardShortcut("e", modifiers: [.command])

                    Button("규칙 복원…") {
                        appDelegate.importRulesFromFile()
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = RuleStore()
    let permission = AccessibilityPermission()
    let eventTap = EventTapManager()
    let status: AppStatus

    override init() {
        self.status = AppStatus()
        super.init()
        // Wire references into shared status so SwiftUI views can access them
        // via @EnvironmentObject instead of NSApp.delegate (unreliable on some
        // SwiftUI launch paths).
        self.status.eventTap = self.eventTap
        self.status.exportAction = { [weak self] in self?.exportRulesToFile() }
        self.status.importAction = { [weak self] in self?.importRulesFromFile() }
    }

    private(set) lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()

    private var cancellables: Set<AnyCancellable> = []
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[CCShortcut] ==================== app launching ====================")
        NSLog("[CCShortcut] bundleID=\(Bundle.main.bundleIdentifier ?? "?") path=\(Bundle.main.bundlePath)")
        NSLog("[CCShortcut] PID=\(ProcessInfo.processInfo.processIdentifier)")

        // Prevent duplicate instances. If another CC Shortcut is already
        // running FROM /Applications, surface it and exit.
        // (이동 중인 구버전은 /Applications 외 경로이므로 무시)
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bid = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .filter { $0.processIdentifier != myPID }
            .filter { $0.bundleURL?.path.hasPrefix("/Applications") == true }
        if !others.isEmpty {
            NSLog("[CCShortcut] ⚠️ \(others.count) other instance(s) of \(bid) running; activating one and terminating self")
            others.first?.activate()
            NSApp.terminate(nil)
            return
        }

        NSLog("[CCShortcut] permission.isTrusted=\(permission.isTrusted)  store.rules=\(store.rules.count) rule(s)")

        setupBindings()
        showMainWindow()

        // Touch the updater so it starts checking for updates per its schedule.
        _ = updaterController

        NSLog("[CCShortcut] applicationDidFinishLaunching done; eventTap.isActive=\(eventTap.isActive)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
    }

    // Keep the app alive in the Dock when the user closes the window —
    // the EventTap must keep running for remapping to work.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Reopen the main window when the user clicks the Dock icon while the
    // window is closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showMainWindow()
        }
        return true
    }

    private func setupBindings() {
        eventTap.updateRules(store.rules)

        store.$rules
            .sink { [weak self] rules in
                self?.eventTap.updateRules(rules)
            }
            .store(in: &cancellables)

        // Initial state at launch.
        if permission.isTrusted {
            eventTap.start()
        }
        status.isEventTapActive = eventTap.isActive

        // React only to actual transitions. On false → true we relaunch the
        // process, because newly granted Accessibility permission isn't always
        // picked up by the running app.
        permission.$isTrusted
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] trusted in
                guard let self else { return }
                if trusted {
                    self.relaunchApp()
                } else {
                    self.eventTap.stop()
                    self.status.isEventTapActive = false
                }
            }
            .store(in: &cancellables)
    }

private func relaunchApp() {
        // 구 인스턴스를 먼저 종료한 뒤 새 인스턴스를 열어야
        // applicationDidFinishLaunching의 중복 인스턴스 체크와
        // 타이밍 경쟁이 생기지 않는다.
        // MoveToApplications와 동일한 "sleep + open -n" 패턴 사용.
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && /usr/bin/open -n \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Backup / Restore

    func exportRulesToFile() {
        let panel = NSSavePanel()
        panel.title = "규칙 백업 저장"
        panel.prompt = "저장"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "CC Shortcut Backup \(formatter.string(from: Date())).json"

        showMainWindow()
        panel.beginSheetModal(for: mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.store.exportRules(to: url)
                self.flashAlert(title: "백업 저장 완료",
                                message: "규칙 \(self.store.rules.count)개를 저장했습니다.\n\(url.lastPathComponent)")
            } catch {
                self.flashAlert(title: "백업 실패",
                                message: error.localizedDescription,
                                style: .warning)
            }
        }
    }

    func importRulesFromFile() {
        let panel = NSOpenPanel()
        panel.title = "백업 파일 선택"
        panel.prompt = "열기"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        showMainWindow()
        panel.beginSheetModal(for: mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.askImportMode { mode in
                guard let mode else { return }
                do {
                    let count = try self.store.importRules(from: url, mode: mode)
                    self.flashAlert(title: "복원 완료",
                                    message: "현재 규칙 수: \(count)개")
                } catch {
                    self.flashAlert(title: "복원 실패",
                                    message: error.localizedDescription,
                                    style: .warning)
                }
            }
        }
    }

    private func askImportMode(completion: @escaping (RuleStore.ImportMode?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "복원 방식을 선택해 주세요"
        alert.informativeText = "현재 등록된 규칙을 모두 삭제하고 백업으로 덮어쓸지,\n아니면 백업 규칙을 현재 목록에 추가할지 선택합니다."
        alert.addButton(withTitle: "덮어쓰기")
        alert.addButton(withTitle: "병합")
        alert.addButton(withTitle: "취소")
        alert.alertStyle = .informational

        if let window = mainWindow {
            alert.beginSheetModal(for: window) { resp in
                switch resp {
                case .alertFirstButtonReturn:  completion(.replace)
                case .alertSecondButtonReturn: completion(.merge)
                default:                        completion(nil)
                }
            }
        } else {
            let resp = alert.runModal()
            switch resp {
            case .alertFirstButtonReturn:  completion(.replace)
            case .alertSecondButtonReturn: completion(.merge)
            default:                        completion(nil)
            }
        }
    }

    private func flashAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "확인")
        if let window = mainWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let content = ContentView()
                .environmentObject(store)
                .environmentObject(permission)
                .environmentObject(status)
            let hosting = NSHostingController(rootView: content)

            let window = NSWindow(contentViewController: hosting)
            window.title = "CC Shortcut"
            window.setContentSize(NSSize(width: 720, height: 520))
            window.minSize = NSSize(width: 700, height: 500)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}
