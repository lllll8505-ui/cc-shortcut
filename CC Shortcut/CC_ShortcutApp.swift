//
//  CC_ShortcutApp.swift
//  CC Shortcut
//

import SwiftUI
import AppKit
import Combine
import Sparkle

@main
struct CC_ShortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("업데이트 확인…") {
                        appDelegate.updaterController.checkForUpdates(nil)
                    }
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = RuleStore()
    let permission = AccessibilityPermission()
    let eventTap = EventTapManager()

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
        setupBindings()
        showMainWindow()

        // Touch the updater so it starts checking for updates per its schedule.
        _ = updaterController
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
                }
            }
            .store(in: &cancellables)
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

    private func showMainWindow() {
        if mainWindow == nil {
            let content = ContentView()
                .environmentObject(store)
                .environmentObject(permission)
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
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}
