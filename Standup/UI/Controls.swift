//
//  Controls.swift
//  Standup
//
//  Custom controls used by the popover.
//

import Cocoa

/// Rounded surface used for cards in the popover
class SurfaceView: NSView {

    var cornerRadius: CGFloat = 18 { didSet { layer?.cornerRadius = cornerRadius } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 0.5
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.07).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        }
    }
}

/// Round raise / lower button: reports when the mouse goes down and when it is released, so the desk can move while it is held
final class HoldButton: NSButton {

    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?

    private var isHovering = false { didSet { updateColors() } }
    private var isPressedDown = false { didSet { updateColors() } }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.4
            updateColors()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        wantsLayer = true
        layer?.borderWidth = 0.5
        updateColors()
    }

    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    /// Follows the mouse until it is released, whether or not it is still over the button
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        isPressedDown = true
        onPressBegan?()

        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]), next.type != .leftMouseUp {
            continue
        }

        isPressedDown = false
        onPressEnded?()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isPressedDown {
                layer?.backgroundColor = NSColor.controlAccentColor.cgColor
                contentTintColor = .white
            } else {
                // Translucent "glass" fill: light in light mode, faint white in dark mode
                let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let base: CGFloat = isDark ? 0.12 : 0.45
                let alpha = (isHovering && isEnabled) ? base + 0.13 : base
                layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
                contentTintColor = .controlAccentColor
            }
            layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        }
    }
}

/// Compact preset action: icon, name and target height
class PresetButton: NSButton {

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    private var isHovering = false { didSet { updateColors() } }

    override var isHighlighted: Bool { didSet { updateColors() } }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
            updateColors()
        }
    }

    var name = "" { didSet { refresh() } }
    var heightText = "" { didSet { refresh() } }

    /// While the desk is travelling to this preset the button turns into "Stop"
    var isStopping = false { didSet { refresh() } }

    init(symbolNames: [String], fallbackSymbol: String) {
        super.init(frame: .zero)

        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 0.5

        iconView.image = Self.symbol(symbolNames + [fallbackSymbol], pointSize: 24)
        iconView.contentTintColor = .controlAccentColor
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        let texts = NSStackView(views: [titleLabel, subtitleLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1

        let row = NSStackView(views: [iconView, texts])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30)
        ])

        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func symbol(_ names: [String], pointSize: CGFloat, weight: NSFont.Weight = .medium) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                return image
            }
        }
        return nil
    }

    private func refresh() {
        titleLabel.stringValue = isStopping ? "Stop" : name
        subtitleLabel.stringValue = isStopping ? "Moving…" : heightText
    }

    /// Child labels must not swallow clicks
    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let alpha: CGFloat = isHighlighted ? 0.20 : ((isHovering && isEnabled) ? 0.13 : (isEnabled ? 0.08 : 0.04))
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        }
    }
}

/// Small circular icon button (e.g. the "more" menu button)
class RoundIconButton: NSButton {

    var diameter: CGFloat = 32

    override var intrinsicContentSize: NSSize { NSSize(width: diameter, height: diameter) }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        wantsLayer = true
        updateColors()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override var isHighlighted: Bool { didSet { updateColors() } }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.16 : 0.06).cgColor
        }
        contentTintColor = .secondaryLabelColor
    }
}

/// A small text link: opens a URL in the default browser, shows the pointing-hand cursor and underlines on hover
final class LinkLabel: NSTextField {

    private let url: URL
    private let fontSize: CGFloat
    private let text: String

    private var isHovering = false { didSet { updateStyle() } }

    init(text: String, url: URL, fontSize: CGFloat = 10) {
        self.text = text
        self.url = url
        self.fontSize = fontSize
        super.init(frame: .zero)

        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
        toolTip = url.absoluteString
        setAccessibilityRole(.link)
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func updateStyle() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment

        attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: isHovering ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
            .underlineStyle: isHovering ? NSUnderlineStyle.single.rawValue : 0,
            .paragraphStyle: paragraph
        ])
    }

    override var alignment: NSTextAlignment {
        didSet { updateStyle() }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSWorkspace.shared.open(url)
    }
}

extension URL {
    /// The author's site, linked from the popover, Preferences and the About panel
    static let authorSite = URL(string: "https://sagan.dev")!
}
