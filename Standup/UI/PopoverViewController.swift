//
//  PopoverViewController.swift
//  Standup
//
//  The popover shown from the menu bar: height, raise / lower and the presets.
//

import Cocoa
import CoreBluetooth

final class PopoverViewController: NSViewController {
    
    private(set) var driver: DeskDriver?
    
    private let scanner = DeskScanner.shared
    
    var messageLabel: NSTextField?
    
    var currentPositionLabel: NSTextField?
    var currentPositionDimenstionLabel: NSTextField?
    var movingCaptionLabel: NSTextField?
    
    var upButton: HoldButton?
    var downButton: HoldButton?
    
    var sitButton: PresetButton?
    var standButton: PresetButton?
    
    // Status indicator
    var statusIndicator: NSView?
    var statusLabel: NSTextField?
    
    weak var popover: NSPopover?
    
    private let popoverWidth: CGFloat = 460
    private let popoverInset: CGFloat = 18
    private var contentStack: NSStackView?
    
    /// Height that fits the content exactly (the root view's own fitting size can be inflated by leftover space)
    var fittingContentHeight: CGFloat {
        return (contentStack?.fittingSize.height ?? 0) + popoverInset * 2
    }
    private var travel: TravelDirection = .idle
    
    init() {
        super.init(nibName: nil, bundle: nil)
        observeScanner()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func observeScanner() {
        scanner.onDeskChange = { [weak self] peripheral in
            self?.updateConnectionLabels()
            if let peripheral = peripheral {
                self?.attach(to: peripheral)
            }
        }

        scanner.onBluetoothStateChange = { [weak self] in
            self?.updateConnectionLabels()
        }

        scanner.start()
    }

    // MARK: - View
    
    private func label(_ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
    
    private func stack(_ views: [NSView], _ orientation: NSUserInterfaceLayoutOrientation, spacing: CGFloat, alignment: NSLayoutConstraint.Attribute) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
        stack.spacing = spacing
        stack.alignment = alignment
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    
    /// Places `content` inside a surface with the given insets
    private func embed(_ content: NSView, in surface: SurfaceView, insets: NSEdgeInsets) {
        content.translatesAutoresizingMaskIntoConstraints = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: surface.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -insets.bottom)
        ])
    }
    
    private func iconTile(_ names: [String], size: CGFloat, symbolSize: CGFloat, radius: CGFloat) -> SurfaceView {
        let tile = SurfaceView()
        tile.cornerRadius = radius
        tile.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: PresetButton.symbol(names, pointSize: symbolSize) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(icon)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: size),
            tile.heightAnchor.constraint(equalToConstant: size),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor)
        ])
        return tile
    }
    
    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        
        // Header
        let title = label(17, .semibold)
        title.stringValue = "Standup"
        
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8)
        ])
        statusIndicator = dot
        
        let status = label(12, .regular, .secondaryLabelColor)
        status.stringValue = "Connecting…"
        statusLabel = status
        
        let statusRow = stack([dot, status], .horizontal, spacing: 6, alignment: .centerY)
        let titles = stack([title, statusRow], .vertical, spacing: 3, alignment: .leading)
        titles.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let more = RoundIconButton(frame: .zero)
        more.image = PresetButton.symbol(["ellipsis"], pointSize: 13, weight: .bold)
        more.target = self
        more.action = #selector(showMoreMenu(_:))
        more.toolTip = "More"
        more.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            more.widthAnchor.constraint(equalToConstant: 32),
            more.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        let deskTile = iconTile(["table.furniture", "desktopcomputer"], size: 44, symbolSize: 22, radius: 12)
        let header = stack([deskTile, titles, more], .horizontal, spacing: 12, alignment: .centerY)
        header.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        let message = NSTextField(wrappingLabelWithString: "")
        message.font = .systemFont(ofSize: 11)
        message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = popoverWidth - 36
        message.stringValue = "Make sure your desk is in pairing mode if it has never connected to this Mac, and that no other app is using it."
        messageLabel = message
        
        // Height card
        let heightCard = SurfaceView()
        let height = NSTextField(labelWithString: "–")
        height.font = .monospacedDigitSystemFont(ofSize: 60, weight: .bold)
        currentPositionLabel = height
        
        let unit = label(18, .semibold, .secondaryLabelColor)
        unit.stringValue = Preferences.shared.unitName
        currentPositionDimenstionLabel = unit
        
        // Number with the unit on a second line, so three digits always fit; "Moving…" sits at the top
        unit.font = .systemFont(ofSize: 16, weight: .semibold)
        let heightColumn = stack([height, unit], .vertical, spacing: -2, alignment: .centerX)
        heightColumn.translatesAutoresizingMaskIntoConstraints = false
        let caption = label(11, .medium, .secondaryLabelColor)
        caption.alignment = .center
        caption.lineBreakMode = .byClipping
        caption.setContentCompressionResistancePriority(.required, for: .horizontal)
        caption.translatesAutoresizingMaskIntoConstraints = false
        movingCaptionLabel = caption
        heightCard.addSubview(heightColumn)
        heightCard.addSubview(caption)
        NSLayoutConstraint.activate([
            heightColumn.centerXAnchor.constraint(equalTo: heightCard.centerXAnchor),
            heightColumn.centerYAnchor.constraint(equalTo: heightCard.centerYAnchor, constant: 4),
            caption.centerXAnchor.constraint(equalTo: heightCard.centerXAnchor),
            caption.topAnchor.constraint(equalTo: heightCard.topAnchor, constant: 10),
            caption.widthAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ])
        
        // Raise / lower pill
        let up = HoldButton(frame: .zero)
        up.image = PresetButton.symbol(["chevron.up"], pointSize: 20, weight: .semibold)
        up.onPressBegan = { [weak self] in self?.driver?.hold(.up) }
        up.onPressEnded = { [weak self] in self?.driver?.stop() }
        up.toolTip = "Raise (hold to move)"
        upButton = up
        
        let down = HoldButton(frame: .zero)
        down.image = PresetButton.symbol(["chevron.down"], pointSize: 20, weight: .semibold)
        down.onPressBegan = { [weak self] in self?.driver?.hold(.down) }
        down.onPressEnded = { [weak self] in self?.driver?.stop() }
        down.toolTip = "Lower (hold to move)"
        downButton = down
        
        [up, down].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                $0.widthAnchor.constraint(equalToConstant: 50),
                $0.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
        
        let pill = SurfaceView()
        pill.cornerRadius = 34
        pill.translatesAutoresizingMaskIntoConstraints = false
        let pillStack = stack([up, down], .vertical, spacing: 8, alignment: .centerX)
        pill.addSubview(pillStack)
        NSLayoutConstraint.activate([
            pillStack.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            pillStack.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        
        // Presets
        let stand = PresetButton(symbolNames: ["figure.stand"], fallbackSymbol: "arrow.up.to.line")
        stand.name = "Move to stand"
        stand.target = self
        stand.action = #selector(self.stand(_:))
        standButton = stand
        
        let sit = PresetButton(symbolNames: ["figure.seated.side", "chair.lounge"], fallbackSymbol: "arrow.down.to.line")
        sit.name = "Move to sit"
        sit.target = self
        sit.action = #selector(self.sit(_:))
        sitButton = sit
        
        let presets = stack([stand, sit], .vertical, spacing: 8, alignment: .leading)
        presets.distribution = .fillEqually
        [stand, sit].forEach { $0.widthAnchor.constraint(equalTo: presets.widthAnchor).isActive = true }
        
        let controls = stack([heightCard, pill, presets], .horizontal, spacing: 10, alignment: .top)
        NSLayoutConstraint.activate([
            controls.heightAnchor.constraint(equalToConstant: 132),
            heightCard.widthAnchor.constraint(equalToConstant: 150),
            heightCard.heightAnchor.constraint(equalTo: controls.heightAnchor),
            pill.widthAnchor.constraint(equalToConstant: 68),
            pill.heightAnchor.constraint(equalTo: controls.heightAnchor),
            presets.heightAnchor.constraint(equalTo: controls.heightAnchor)
        ])
        
        // Root layout
        let footer = LinkLabel(text: "Made by sagan.dev", url: .authorSite)
        footer.alignment = .center
        let content = stack([header, message, controls, footer], .vertical, spacing: 12, alignment: .leading)
        content.setCustomSpacing(8, after: controls)
        [header, message, controls, footer].forEach {
            $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            $0.setContentHuggingPriority(.required, for: .vertical)
        }
        root.addSubview(content)
        contentStack = content
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: popoverWidth),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            {
                let fit = content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
                fit.priority = .defaultLow
                return fit
            }(),
            content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18)
        ])
    }
    
    #if DEBUG
    /// Debug helper for offscreen rendering: shows the connected state without a real desk
    func previewConnected() {
        statusLabel?.stringValue = "Connected · Desk 7167"
        statusIndicator?.layer?.backgroundColor = NSColor.systemGreen.cgColor
        messageLabel?.isHidden = true
        currentPositionLabel?.stringValue = ProcessInfo.processInfo.environment["RENDER_HEIGHT"] ?? "70"
        if ProcessInfo.processInfo.environment["RENDER_MOVING"] != nil { movingCaptionLabel?.stringValue = "Moving…" }
        [upButton, downButton, standButton].forEach { ($0 as? NSControl)?.isEnabled = true }
        sitButton?.isEnabled = false
        refreshDisplay()
        standButton?.heightText = "~ 118 cm"
    }
    #endif
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        statusIndicator?.layer?.backgroundColor = NSColor.systemOrange.cgColor
        
        if let height = driver?.currentHeight {
            showHeight(height)
        }

        updateConnectionLabels()
        refreshDisplay()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        refreshDisplay()
    }
    
    /// Refreshes everything that depends on preferences, and resizes the popover to fit
    func refreshDisplay() {
        guard isViewLoaded else { return }
        
        currentPositionDimenstionLabel?.stringValue = Preferences.shared.unitName
        standButton?.heightText = "~ \(formatted(Preferences.shared.standingHeight)) \(Preferences.shared.unitName)"
        sitButton?.heightText = "~ \(formatted(Preferences.shared.sittingHeight)) \(Preferences.shared.unitName)"
        
        if let height = driver?.currentHeight {
            showHeight(height)
        }

        resizeToFit()
    }
    
    private func resizeToFit() {
        guard isViewLoaded else { return }
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: popoverWidth, height: fittingContentHeight)
    }
    
    private func formatted(_ centimeters: Float) -> String {
        let value = Preferences.shared.usesMetricUnits ? centimeters : centimeters.centimetersToInches
        return "\(Int(value.rounded()))"
    }
    
    // MARK: - Connection

    private struct ConnectionStatus {
        var text: String
        var color: NSColor
        var hint: String
    }

    private func connectionStatus() -> ConnectionStatus {
        let peripheral = scanner.desk
        let connected = driver != nil && peripheral != nil

        var status = ConnectionStatus(
            text: connected ? "Connected" : "Not connected",
            color: connected ? .systemGreen : .systemRed,
            hint: "Make sure your desk is in pairing mode if it has never connected to this Mac, and that no other app is using it.")

        if let central = scanner.central {
            switch central.state {
            case .poweredOn:
                status.text = connected ? "Connected" : "Searching for nearby desks"
                status.color = connected ? .systemGreen : .systemOrange
            case .poweredOff:
                status.text = "Bluetooth is off"
            case .resetting:
                status.text = "Reconnecting"
                status.color = .systemOrange
            case .unauthorized:
                status.text = "Bluetooth not allowed"
            case .unsupported:
                status.text = "Bluetooth not supported"
            case .unknown:
                status.text = "Bluetooth status unknown"
            @unknown default:
                break
            }

            if central.authorization == .denied {
                status.text = "Bluetooth access was denied"
                status.hint = "Standup needs Bluetooth to talk to your desk. Allow it in System Settings → Privacy & Security → Bluetooth."
            }
        }

        if connected, let name = peripheral?.name {
            status.text += " · \(name)"
        }
        return status
    }

    func updateConnectionLabels() {
        guard isViewLoaded else { return }

        let connected = driver != nil && scanner.desk != nil
        let status = connectionStatus()

        statusLabel?.stringValue = status.text
        statusIndicator?.layer?.backgroundColor = status.color.cgColor
        messageLabel?.stringValue = status.hint
        messageLabel?.isHidden = connected

        [upButton, downButton].forEach { $0?.isEnabled = connected }
        if let height = driver?.currentHeight, connected {
            showHeight(height)
        } else {
            sitButton?.isEnabled = false
            standButton?.isEnabled = false
        }

        updateCaption()
        resizeToFit()
    }

    /// Starts driving the desk that just connected
    private func attach(to peripheral: CBPeripheral) {
        let link = DeskLink(peripheral: peripheral)
        let driver = DeskDriver(link: link)
        self.driver = driver

        driver.observeHeight { [weak self] height in
            self?.showHeight(height)
        }

        driver.onDirectionChange = { [weak self] direction in
            self?.travel = direction
            if direction == .idle {
                self?.sitButton?.isStopping = false
                self?.standButton?.isStopping = false
            }
            self?.updateCaption()
        }

        updateConnectionLabels()
    }

    /// Shows the height and enables the presets that are not already reached
    private func showHeight(_ height: Float) {
        guard isViewLoaded else { return }

        let shown = Preferences.shared.usesMetricUnits ? height : height.centimetersToInches
        currentPositionLabel?.stringValue = "\(Int(shown.rounded()))"

        let connected = scanner.desk != nil
        sitButton?.isEnabled = connected && Preferences.shared.sittingHeight.rounded() != height.rounded()
        standButton?.isEnabled = connected && Preferences.shared.standingHeight.rounded() != height.rounded()

        updateCaption()
    }

    /// "Moving…" at the top of the height card while the desk travels, empty otherwise (the height is shown below)
    private func updateCaption() {
        movingCaptionLabel?.stringValue = (travel != .idle) ? "Moving…" : ""
    }

    /// Called just before the popover appears
    func popoverWillShow() {
        scanner.start()
        scanner.reconnectIfNeeded()
        refreshDisplay()
    }

    // MARK: - Actions

    @objc private func sit(_ sender: Any) {
        togglePreset(sitButton, target: .sit)
    }

    @objc private func stand(_ sender: Any) {
        togglePreset(standButton, target: .stand)
    }

    /// A preset button starts the trip; while it is travelling the same button stops it
    private func togglePreset(_ button: PresetButton?, target: DeskTarget) {
        guard let button = button, let driver = driver else { return }

        if button.isStopping {
            driver.stop()
        } else {
            button.isStopping = true
            driver.go(to: target)
        }
    }

    @objc private func showMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let preferences = menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: "")
        preferences.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Standup", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openPreferences() {
        popover?.performClose(self)
        SettingsWindowController.shared.show(driver: driver)
    }
}
