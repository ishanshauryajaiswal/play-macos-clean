import AppKit
import Carbon

/// Handles global hot-key registration and presents the floating `ContentPanel`.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var contentWindow: NSWindow?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the app out of Dock / Cmd-Tab.
        NSApplication.shared.setActivationPolicy(.accessory)
        registerGlobalHotKey()
    }

    // MARK: - Panel presentation
    @objc func showContentWindow() {
        if let window = contentWindow, window.isVisible {
            window.close()
            contentWindow = nil
        } else {
            let panel = ContentPanel()
            panel.makeKeyAndOrderFront(nil)
            contentWindow = panel
        }
    }

    // MARK: - Hot-key (⌘⇧A)
    private func registerGlobalHotKey() {
        let modifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)      // ⌘ + ⇧
        let keyCode: UInt32 = UInt32(kVK_ANSI_A)                       // "A"
        let hotKeyID = EventHotKeyID(signature: OSType("lazi".fourCharCodeValue), id: 1)

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            NSLog("[HotKey] Registration failed – status: \(status)")
            return
        }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                if hk.id == 1, let userData {
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    delegate.showContentWindow()
                }
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

// MARK: - Helpers
private extension String {
    /// Converts up to the first four UTF-16 scalars to an OSType.
    var fourCharCodeValue: OSType {
        unicodeScalars.prefix(4).reduce(0) { ($0 << 8) + OSType($1.value) }
    }
} 