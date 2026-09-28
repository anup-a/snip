import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var session: CaptureSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-demo"), args.count > i + 2 {
            DemoRenderer.render(script: args[i + 1], to: args[i + 2])
            exit(0)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Snip")

        let menu = NSMenu()
        let take = NSMenuItem(title: "Take Screenshot", action: #selector(captureFromMenu), keyEquivalent: "a")
        take.keyEquivalentModifierMask = [.command, .shift]
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
        menu.addItem(NSMenuItem(title: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.capture()
        }

        // Lets scripts trigger a capture: post "com.anup.snip.capture" as a distributed notification.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.anup.snip.capture"), object: nil, queue: .main) { [weak self] _ in
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
        NSLog("Snip capture requested (screen access: \(CGPreflightScreenCaptureAccess()))")
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
                NSLog("Snip capture failed: \(error)")
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
            NSLog("Snip login item error: \(error)")
        }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
