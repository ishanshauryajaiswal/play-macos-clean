//
//  laziApp.swift
//  lazi
//
//  Created by Shaurya Jaiswal on 24/07/25.
//

import SwiftUI
import AppKit
import Carbon
import CoreData

@main
struct laziApp: App {
    // AppDelegate handles hot-key and floating panel logic.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView() // Main SwiftUI scene intentionally empty.
        }
    }
}

// MARK: - Embedded AppDelegate (fallback)
class AppDelegate: NSObject, NSApplicationDelegate {
    private var recorder = AudioRecorder()
    private var contentWindow: ContentPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        registerHotKey()

        logDatabaseSummary()
    }

    /// Logs number of transcripts and the five most recent entries.
    private func logDatabaseSummary() {
        let context = PersistenceController.shared.container.viewContext

        // Total count
        let countRequest: NSFetchRequest<Item> = Item.fetchRequest()
        do {
            let total = try context.count(for: countRequest)
            NSLog("[DB] Total transcripts stored: \(total)")
        } catch {
            NSLog("[DB] Failed to count transcripts: \(error.localizedDescription)")
        }

        // Fetch recent 5
        let recentRequest: NSFetchRequest<Item> = Item.fetchRequest()
        recentRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        recentRequest.fetchLimit = 5

        do {
            let recent = try context.fetch(recentRequest)
            for (index, item) in recent.enumerated() {
                let dateStr = item.timestamp?.description ?? "nil"
                let textPreview = item.text?.prefix(80) ?? ""
                NSLog("[DB] #\(index + 1): [\(dateStr)] \(textPreview)")
            }
        } catch {
            NSLog("[DB] Failed to fetch recent transcripts: \(error.localizedDescription)")
        }
    }

    @objc func togglePanel() {
        if let window = contentWindow, window.isVisible {
            window.close()
            contentWindow = nil
        } else {
            let panel = ContentPanel()
            contentWindow = panel
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func registerHotKey() {
        let modifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_A)
        let hotKeyID = EventHotKeyID(signature: OSType("lazi".fourCharCodeValue), id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if hk.id == 1, let userData {
                Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue().togglePanel()
            }
            return noErr
        }, 1, &spec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandlerRef)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

private extension String {
    var fourCharCodeValue: OSType { unicodeScalars.prefix(4).reduce(0) { ($0 << 8) + OSType($1.value) } }
}
