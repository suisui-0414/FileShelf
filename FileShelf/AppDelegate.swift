import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var shelfWindow: ShelfPanel?
    private var preferencesWindow: NSWindow?
    let viewModel = ShelfViewModel()

    private var dragMonitors: [Any] = []
    private var autoShowedShelf = false
    private var dwellTimer: Timer?

    private var dwellInterval: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "dwellInterval")
        return v > 0 ? v : 0.5
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "dwellEnabled":      true,
            "dwellInterval":     0.5,
            "shortcutEnabled":   false,
            "shortcutKeyCode":   0,
            "shortcutModifiers": 0,
        ])
        setupStatusItem()
        setupShelfWindow()
        startDragMonitoring()
        setupShortcutMonitoring()
        shelfWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dwellTimer?.invalidate()
        dragMonitors.forEach { NSEvent.removeMonitor($0) }
        HotKeyManager.shared.unregister()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "FileShelf")
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "設定...", action: #selector(openPreferences), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "FileShelf を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
        } else {
            toggleShelf()
        }
    }

    @objc func toggleShelf() {
        guard let panel = shelfWindow else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Preferences

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "FileShelf 設定"
            window.contentView = NSHostingView(rootView: PreferencesView())
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Shelf Window

    private func setupShelfWindow() {
        let hostingView = NSHostingView(rootView: ContentView(viewModel: viewModel))
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 400),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "FileShelf"

        // SwiftUI 側は touchesBegan 等を実装しないため、未処理のタッチイベントは
        // レスポンダチェーンを通じてこのコンテナビューまで伝播してくる
        let touchContainer = TouchDragView(frame: hostingView.frame)
        hostingView.autoresizingMask = [.width, .height]
        touchContainer.addSubview(hostingView)
        panel.contentView = touchContainer
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("FileShelfPanel")

        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - panel.frame.width - 20
            let y = screen.visibleFrame.maxY - panel.frame.height - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        shelfWindow = panel
    }

    // MARK: - Drag Monitoring

    private func startDragMonitoring() {
        let onDown = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.dwellTimer?.invalidate()
            self?.autoShowedShelf = false
        }

        let onDrag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self, !self.autoShowedShelf else { return }
            guard UserDefaults.standard.bool(forKey: "dwellEnabled") else {
                self.dwellTimer?.invalidate()
                return
            }

            let pb = NSPasteboard(name: .drag)
            let fileTypes: [NSPasteboard.PasteboardType] = [.fileURL, .init("NSFilenamesPboardType")]
            guard pb.types?.contains(where: { fileTypes.contains($0) }) == true else {
                self.dwellTimer?.invalidate()
                return
            }

            self.dwellTimer?.invalidate()
            self.dwellTimer = Timer.scheduledTimer(withTimeInterval: self.dwellInterval, repeats: false) { [weak self] _ in
                guard let self, !self.autoShowedShelf else { return }
                self.autoShowedShelf = true
                self.shelfWindow?.makeKeyAndOrderFront(nil)
            }
        }

        let onUp = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.dwellTimer?.invalidate()
            self?.autoShowedShelf = false
        }

        dragMonitors = [onDown, onDrag, onUp].compactMap { $0 }
    }

    // MARK: - Shortcut Monitoring

    private func setupShortcutMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshShortcutMonitors),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        refreshShortcutMonitors()
    }

    // Carbon の RegisterEventHotKey を使うことで、アクセシビリティ権限なしに
    // 他アプリにフォーカスがある状態でもショートカットを受け取れる
    @objc private func refreshShortcutMonitors() {
        HotKeyManager.shared.unregister()

        guard UserDefaults.standard.bool(forKey: "shortcutEnabled") else { return }
        let keyCode = UInt32(UserDefaults.standard.integer(forKey: "shortcutKeyCode"))
        guard keyCode != 0 else { return }

        let rawMods = UInt(bitPattern: UserDefaults.standard.integer(forKey: "shortcutModifiers"))
        let nsMods = NSEvent.ModifierFlags(rawValue: rawMods)
        let carbonMods = HotKeyManager.carbonModifiers(from: nsMods)

        HotKeyManager.shared.register(keyCode: keyCode, carbonModifiers: carbonMods) { [weak self] in
            self?.toggleShelf()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - ShelfPanel

class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            orderOut(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
