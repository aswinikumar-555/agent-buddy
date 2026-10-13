// Quick capture: press ⌥Space anywhere, type, press Return. It goes on your to-do
// list. Start with "@project " to send it to that project's agent instead.
import AppKit
import Carbon
import SwiftUI

final class QuickCapture {
    static let shared = QuickCapture()
    var onCapture: (String) -> Void = { _ in }

    var enabled = false {
        didSet { if enabled != oldValue { enabled ? register() : unregister() } }
    }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var window: NSPanel?
    private var previousApp: NSRunningApplication?
    private let draft = CardDraft()

    private func register() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { QuickCapture.shared.show() }
            return noErr
        }, 1, &type, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x4142_5143), id: 1) // "ABQC"
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil
    }

    func show() {
        if window == nil {
            let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 64),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: CaptureView(draft: draft, submit: { [weak self] in self?.submit() },
                                                                   cancel: { [weak self] in self?.hide() }))
            window = panel
        }
        guard let window, let screen = NSScreen.main?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: screen.midX - 260, y: screen.maxY - screen.height * 0.28))
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func submit() {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.text = ""
        hide()
        if !text.isEmpty { onCapture(text) }
    }

    private func hide() {
        window?.orderOut(nil)
        previousApp?.activate() // back to the app you were in
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct CaptureView: View {
    @ObservedObject var draft: CardDraft
    let submit: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.blue)
            TextField("Add a to-do… (or @project message for its agent)", text: $draft.text)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .onSubmit(submit)
                .onExitCommand(perform: cancel)
        }
        .padding(.horizontal, 18)
        .frame(width: 520, height: 64)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.bg))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
        .environment(\.colorScheme, Palette.scheme)
    }
}
