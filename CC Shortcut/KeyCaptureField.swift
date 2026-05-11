//
//  KeyCaptureField.swift
//  CC Shortcut
//
//  Tappable field that enters "capture mode" and records the next key combo
//  the user presses. Uses a local NSEvent monitor so the keystroke is consumed
//  (no menu/text-field side effects).
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct KeyCaptureField: View {
    let title: String
    @Binding var keyCode: Int?
    @Binding var modifiers: Modifiers

    @State private var isCapturing = false

    var body: some View {
        Button(action: { isCapturing.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: isCapturing ? "record.circle" : "keyboard")
                    .foregroundStyle(isCapturing ? Color.accentColor : .secondary)
                Text(displayText)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isCapturing {
                    Text("ESC 취소")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isCapturing ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isCapturing ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            KeyCaptureMonitor(isCapturing: isCapturing) { code, mods in
                if code == kVK_Escape && mods.isEmpty {
                    isCapturing = false
                    return
                }
                keyCode = code
                modifiers = mods
                isCapturing = false
            }
        )
    }

    private var displayText: String {
        if isCapturing {
            return "키를 눌러주세요…"
        }
        if let code = keyCode {
            return modifiers.symbolString + KeyCodeMap.displayName(for: code)
        }
        return title
    }

    private var textColor: Color {
        if isCapturing { return .secondary }
        return keyCode == nil ? .secondary : .primary
    }
}

private struct KeyCaptureMonitor: NSViewRepresentable {
    let isCapturing: Bool
    let onCapture: (Int, Modifiers) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isCapturing: isCapturing, onCapture: onCapture)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var localMonitor: Any?
        private var usingEventTap = false

        private var eventTap: EventTapManager? {
            (NSApp.delegate as? AppDelegate)?.eventTap
        }

        func update(isCapturing: Bool, onCapture: @escaping (Int, Modifiers) -> Void) {
            if isCapturing {
                install(onCapture: onCapture)
            } else {
                uninstall()
            }
        }

        private func install(onCapture: @escaping (Int, Modifiers) -> Void) {
            uninstall()

            // Prefer the global CGEventTap when available — it intercepts
            // events before macOS system shortcuts (⌘⇧3/4/5, Mission Control,
            // etc.), so the user can register any combo as a trigger.
            if let tap = eventTap, tap.isActive {
                tap.setCaptureCallback { keyCode, mods in
                    DispatchQueue.main.async { onCapture(keyCode, mods) }
                }
                usingEventTap = true
                return
            }

            // Fallback: in-app local monitor (system shortcuts still take
            // precedence here, but it's enough before Accessibility is granted).
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = Modifiers(nsFlags: event.modifierFlags)
                let code = Int(event.keyCode)
                onCapture(code, mods)
                return nil
            }
        }

        private func uninstall() {
            if usingEventTap {
                eventTap?.setCaptureCallback(nil)
                usingEventTap = false
            }
            if let m = localMonitor {
                NSEvent.removeMonitor(m)
                localMonitor = nil
            }
        }

        deinit { uninstall() }
    }
}
