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

    @EnvironmentObject private var status: AppStatus
    @State private var isCapturing = false

    var body: some View {
        Button(action: {
            isCapturing.toggle()
            NSLog("[CCShortcut] KeyCaptureField button click — isCapturing now=\(isCapturing) (title='\(title)')")
        }) {
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
            KeyCaptureMonitor(
                isCapturing: isCapturing,
                eventTap: status.eventTap
            ) { code, mods in
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
    let eventTap: EventTapManager?
    let onCapture: (Int, Modifiers) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isCapturing: isCapturing, eventTap: eventTap, onCapture: onCapture)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var localMonitor: Any?
        private weak var installedTap: EventTapManager?

        func update(
            isCapturing: Bool,
            eventTap: EventTapManager?,
            onCapture: @escaping (Int, Modifiers) -> Void
        ) {
            NSLog("[CCShortcut] KeyCaptureMonitor.update isCapturing=\(isCapturing), eventTap=\(eventTap == nil ? "nil" : "ok") isActive=\(eventTap?.isActive == true)")
            if isCapturing {
                install(eventTap: eventTap, onCapture: onCapture)
            } else {
                uninstall()
            }
        }

        private func install(
            eventTap: EventTapManager?,
            onCapture: @escaping (Int, Modifiers) -> Void
        ) {
            uninstall()

            // Prefer the global CGEventTap (passed from AppStatus).
            if let tap = eventTap, tap.isActive {
                NSLog("[CCShortcut]   → installing capture callback on EventTapManager")
                tap.setCaptureCallback { keyCode, mods in
                    DispatchQueue.main.async { onCapture(keyCode, mods) }
                }
                installedTap = tap
                return
            }

            // Fallback: in-app local monitor (no system shortcut interception).
            NSLog("[CCShortcut]   → falling back to NSEvent.addLocalMonitorForEvents")
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = Modifiers(nsFlags: event.modifierFlags)
                let code = Int(event.keyCode)
                onCapture(code, mods)
                return nil
            }
        }

        private func uninstall() {
            if let tap = installedTap {
                tap.setCaptureCallback(nil)
                installedTap = nil
            }
            if let m = localMonitor {
                NSEvent.removeMonitor(m)
                localMonitor = nil
            }
        }

        deinit { uninstall() }
    }
}
