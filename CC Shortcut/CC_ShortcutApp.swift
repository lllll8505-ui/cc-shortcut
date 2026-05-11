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
        Settings {
            EmptyView()
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
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupBindings()
        setupStatusItem()
        showMainWindow()

        if permission.isTrusted {
            eventTap.start()
        }

        // Touch the updater so it starts checking for updates per its schedule.
        _ = updaterController
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
    }

    private func setupBindings() {
        eventTap.updateRules(store.rules)

        store.$rules
            .sink { [weak self] rules in
                self?.eventTap.updateRules(rules)
            }
            .store(in: &cancellables)

        // Initial state: react to the value present at launch.
        if permission.isTrusted {
            eventTap.start()
        }

        // Skip the initial emission so we only react to actual transitions.
        // On false → true transition we relaunch, because ad-hoc-signed builds
        // often can't pick up newly granted Accessibility permission without
        // a fresh process.
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

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "command.square",
                accessibilityDescription: "CC Shortcut"
            )
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        let isCtrlClick = event?.modifierFlags.contains(.control) ?? false

        if isRightClick || isCtrlClick {
            showContextMenu()
        } else {
            toggleMainWindow()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "설정 열기",
            action: #selector(showWindowAction),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let statusTitle = permission.isTrusted
            ? "상태: 활성화됨"
            : "상태: 권한 필요"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let countItem = NSMenuItem(
            title: "등록된 규칙: \(store.rules.count)개",
            action: nil,
            keyEquivalent: ""
        )
        countItem.isEnabled = false
        menu.addItem(countItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "업데이트 확인…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
        self.statusItem?.button?.performClick(nil)
        self.statusItem?.menu = nil
    }

    @objc private func showWindowAction() {
        showMainWindow()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
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
            window.titlebarAppearsTransparent = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenAuxiliary]
            window.center()
            mainWindow = window
        }
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func toggleMainWindow() {
        if let window = mainWindow, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }
}
