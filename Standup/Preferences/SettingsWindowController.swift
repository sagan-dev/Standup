//
//  SettingsWindowController.swift
//  Standup
//
//  The Preferences window, built in code.
//

import Cocoa

final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private var driver: DeskDriver? {
        didSet { refresh() }
    }
    private weak var observedDriver: DeskDriver?

    // Heights
    private let currentHeightField = SettingsWindowController.makeNumberField()
    private let standingField = SettingsWindowController.makeNumberField()
    private let sittingField = SettingsWindowController.makeNumberField()
    private let unitsPopUp = NSPopUpButton(frame: .zero, pullsDown: false)

    private let loginCheckbox = NSButton(checkboxWithTitle: "Open Standup at login", target: nil, action: nil)

    private let contentWidth: CGFloat = 340

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the window; `driver` lets the current-height field reflect (and calibrate against) the desk
    func show(driver: DeskDriver?) {
        self.driver = driver
        if let driver = driver, observedDriver !== driver {
            observedDriver = driver
            driver.observeHeight { [weak self] _ in self?.refreshCurrentHeight() }
        }
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Building

    private static func makeNumberField() -> NSTextField {
        let field = NSTextField()
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        return field
    }

    private func buildInterface() {
        unitsPopUp.addItems(withTitles: ["cm", "in"])
        [currentHeightField, standingField, sittingField].forEach {
            $0.target = self
        }
        currentHeightField.action = #selector(calibrateHeight)
        standingField.action = #selector(standingHeightChanged)
        sittingField.action = #selector(sittingHeightChanged)
        unitsPopUp.target = self
        unitsPopUp.action = #selector(unitsChanged)

        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginToggled)

        let column = NSStackView(views: [
            heading("Heights"),
            row("Current height", currentHeightField),
            row("Standing height", standingField),
            row("Sitting height", sittingField),
            row("Units", unitsPopUp),
            divider(),
            loginCheckbox,
            authorLink()
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        column.translatesAutoresizingMaskIntoConstraints = false

        // Full-width rows
        for view in column.arrangedSubviews {
            view.widthAnchor.constraint(equalToConstant: contentWidth - 40).isActive = true
        }

        let container = NSView()
        container.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            column.topAnchor.constraint(equalTo: container.topAnchor),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        window?.contentView = container
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func authorLink() -> NSTextField {
        let link = LinkLabel(text: "Standup by Michal Sagan — sagan.dev", url: .authorSite)
        link.alignment = .center
        return link
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)

        // A flexible spacer pushes the control to the right edge
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let stack = NSStackView(views: [label, spacer, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        return stack
    }

    // MARK: - Showing values

    private func displayed(_ centimeters: Float) -> String {
        let value = Preferences.shared.usesMetricUnits ? centimeters : centimeters.centimetersToInches
        return String(format: "%.1f", value)
    }

    private func refresh() {
        let prefs = Preferences.shared

        standingField.stringValue = displayed(prefs.standingHeight)
        sittingField.stringValue = displayed(prefs.sittingHeight)
        unitsPopUp.selectItem(at: prefs.usesMetricUnits ? 0 : 1)
        refreshCurrentHeight()

        loginCheckbox.state = prefs.launchAtLogin ? .on : .off
    }

    private func refreshCurrentHeight() {
        currentHeightField.isEnabled = driver?.currentHeight != nil
        if let height = driver?.currentHeight {
            currentHeightField.stringValue = displayed(height + Preferences.shared.heightCalibration)
        } else {
            currentHeightField.stringValue = ""
        }
    }

    /// Reads a number the user typed, converted to centimetres
    private func centimeters(from field: NSTextField) -> Float? {
        guard let value = Float(field.stringValue.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return Preferences.shared.usesMetricUnits ? value : value.inchesToCentimeters
    }

    // MARK: - Actions

    @objc private func calibrateHeight() {
        guard let typed = centimeters(from: currentHeightField), let raw = driver?.currentHeight else { return refresh() }
        Preferences.shared.heightCalibration = typed - raw
    }

    @objc private func standingHeightChanged() {
        if let value = centimeters(from: standingField) { Preferences.shared.standingHeight = value }
        refresh()
    }

    @objc private func sittingHeightChanged() {
        if let value = centimeters(from: sittingField) { Preferences.shared.sittingHeight = value }
        refresh()
    }

    @objc private func unitsChanged() {
        Preferences.shared.usesMetricUnits = unitsPopUp.indexOfSelectedItem == 0
        refresh()
    }

    @objc private func loginToggled() {
        Preferences.shared.launchAtLogin = loginCheckbox.state == .on
    }
}
