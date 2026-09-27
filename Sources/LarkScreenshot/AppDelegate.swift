import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var session: CaptureSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Lark Screenshot")

        let menu = NSMenu()
        let take = NSMenuItem(title: "Take Screenshot", action: #selector(captureFromMenu), keyEquivalent: "a")
        take.keyEquivalentModifierMask = [.control, .shift]
        take.target = self
        menu.addItem(take)
        menu.addItem(.separator())
        let permission = NSMenuItem(title: "Screen Recording Permission…", action: #selector(showPermission), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lark Screenshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | shiftKey)) { [weak self] in
            self?.capture()
        }

        // Lets scripts trigger a capture: post "com.anup.lark-screenshot.capture" as a distributed notification.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.anup.lark-screenshot.capture"), object: nil, queue: .main) { [weak self] _ in
            self?.capture()
        }

        if !CGPreflightScreenCaptureAccess() {
            PermissionWindow.show()
        }
    }

    @objc private func captureFromMenu() {
        // Let the status menu finish closing so it isn't in the capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.capture() }
    }

    func capture() {
        NSLog("Lark Screenshot capture requested (screen access: \(CGPreflightScreenCaptureAccess()))")
        guard session == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            PermissionWindow.show()
            return
        }
        Task { @MainActor in
            do {
                let shots = try await ScreenCapturer.captureAllScreens()
                guard !shots.isEmpty else { return }
                let s = CaptureSession(shots: shots) { [weak self] in self?.session = nil }
                self.session = s
                s.begin()
            } catch {
                NSLog("Lark Screenshot capture failed: \(error)")
            }
        }
    }

    @objc private func showPermission() { PermissionWindow.show() }

    @objc private func toggleLaunchAtLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Lark Screenshot login item error: \(error)")
        }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
