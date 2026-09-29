//
//  StatusItemController.swift
//  Standup
//
//  The menu bar item: a popover on left click, a menu on right click.
//

import Cocoa

final class StatusItemController: NSObject {

    let content = PopoverViewController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let menu = NSMenu(title: "Standup")

    override init() {
        super.init()

        popover.behavior = .transient
        popover.contentViewController = content
        content.popover = popover

        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        // Placeholder glyph until the final logo is added to the asset catalog
        let symbol = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        button.image = NSImage(systemSymbolName: "arrow.up.and.down", accessibilityDescription: "Standup")?.withSymbolConfiguration(symbol)
        button.image?.isTemplate = true
        button.toolTip = "Standup"

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        menu.addItem(item("Move to sit", #selector(moveToSit)))
        menu.addItem(item("Move to stand", #selector(moveToStand)))
        menu.addItem(.separator())
        menu.addItem(item("Preferences…", #selector(showPreferences)))
        menu.addItem(item("About Standup", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Standup", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            menu.popUp(positioning: nil, at: NSPoint(x: -15, y: sender.bounds.maxY + 6), in: sender)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            content.popoverWillShow()
        }
    }

    // MARK: - Menu actions

    @objc private func moveToSit() {
        DeskDriver.shared?.go(to: .sit)
    }

    @objc private func moveToStand() {
        DeskDriver.shared?.go(to: .stand)
    }

    @objc func showPreferences() {
        popover.performClose(nil)
        SettingsWindowController.shared.show(driver: DeskDriver.shared)
    }

    @objc private func showAbout() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)

        let credits = NSMutableAttributedString(string: "Standup by Michal Sagan — ", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        credits.append(NSAttributedString(string: "sagan.dev", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL.authorSite
        ]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Standup",
            .credits: credits
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
