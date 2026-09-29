//
//  AppDelegate.swift
//  Standup
//

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu bar utility: no Dock icon
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppDelegate.makeMainMenu()

        if Preferences.shared.isFirstRun {
            Preferences.shared.launchAtLogin = true
            Preferences.shared.isFirstRun = false
        }

        let controller = StatusItemController()
        statusController = controller

        #if DEBUG
        runDebugHooks(with: controller.content)
        #endif
    }

    /// Only needed so that copy and paste work in text fields; an accessory app shows no menu bar of its own
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Standup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }

    // MARK: - Debugging

    #if DEBUG
    /// Environment switches for development: RENDER_POPOVER_TO and RENDER_SETTINGS_TO render the UI to a PNG
    private func runDebugHooks(with content: PopoverViewController) {
        let environment = ProcessInfo.processInfo.environment

        if let path = environment["RENDER_POPOVER_TO"] {
            renderPopover(content, to: path, environment: environment)
        }

        if let path = environment["RENDER_SETTINGS_TO"], let view = SettingsWindowController.shared.window?.contentView {
            view.layoutSubtreeIfNeeded()
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
            view.layoutSubtreeIfNeeded()
            view.appearance = NSAppearance(named: .aqua)
            save(view, to: path)
            exit(0)
        }
    }

    /// Renders the popover content offscreen so the layout can be reviewed without screen access
    private func renderPopover(_ content: PopoverViewController, to path: String, environment: [String: String]) {
        let view = content.view
        if environment["RENDER_CONNECTED"] != nil { content.previewConnected() }
        content.refreshDisplay()

        // The popover forces its content view to the preferred size; do the same here
        let height = content.fittingContentHeight
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        view.frame = NSRect(x: 0, y: 0, width: 460, height: height)
        view.layoutSubtreeIfNeeded()
        view.appearance = NSAppearance(named: environment["RENDER_DARK"] != nil ? .darkAqua : .aqua)

        save(view, to: path)
        exit(0)
    }

    private func save(_ view: NSView, to path: String) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent((path as NSString).lastPathComponent)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
        print("RENDERED \(output.path)")
    }
    #endif
}
