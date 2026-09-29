//
//  DeskDriver.swift
//  Standup
//
//  Decides what the desk does: travel to a height or move while a button is held.
//
//  The desk only keeps moving while it keeps receiving a command, and it coasts a little after "stop".
//  The driver therefore repeats the command on a short pulse and stops slightly before the target.
//

import Cocoa

enum TravelDirection {
    case up, down, idle
}

final class DeskDriver {

    static var shared: DeskDriver?

    let link: DeskLink

    /// Fires whenever the direction of travel changes
    var onDirectionChange: ((TravelDirection) -> Void)?

    private(set) var direction: TravelDirection = .idle {
        didSet {
            if direction != oldValue { onDirectionChange?(direction) }
        }
    }

    var currentHeight: Float? { link.height }

    // MARK: - Tuning

    private let pulseInterval: TimeInterval = 0.2
    private let coastDistance: Float = 0.4        // stop this far before the target, the desk keeps rolling
    private let stallTimeout: TimeInterval = 1.5  // give up if the height stops changing

    // MARK: - State

    private enum Mode {
        case idle
        case holding(TravelDirection)
        case seeking(target: Float, coast: Float, deadline: Date?, done: (() -> Void)?)
    }

    private var mode: Mode = .idle
    private var pulse: Timer?
    private var lastProgress = (height: Float(0), time: Date())
    private var heightObservers = [(Float) -> Void]()

    init(link: DeskLink) {
        self.link = link

        link.onHeightChange = { [weak self] height in
            guard let self = self else { return }
            self.evaluateSeek()
            self.heightObservers.forEach { $0(height) }
        }

        DeskDriver.shared = self

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            DeskScanner.shared.reconnectIfNeeded()
        }
    }

    func observeHeight(_ observer: @escaping (Float) -> Void) {
        heightObservers.append(observer)
    }

    // MARK: - Commands

    /// Travels to the height of a target and stops there
    func go(to target: DeskTarget) {
        takeOver()
        seek(to: Preferences.shared.height(for: target), coast: coastDistance, timeout: nil, done: nil)
    }

    /// Moves while a button is held; call `stop()` on release
    func hold(_ direction: TravelDirection) {
        guard direction != .idle else { return }
        takeOver()
        mode = .holding(direction)
        send(direction)
        startPulse()
    }

    /// A small manual step (used by scripting)
    func step(_ direction: TravelDirection, distance: Float = 1.0) {
        guard direction != .idle, let current = currentHeight else { return }
        takeOver()
        let sign: Float = direction == .up ? 1 : -1
        seek(to: current + sign * distance, coast: 0.2, timeout: 3, done: nil)
    }

    func stop() {
        takeOver()
        link.send(.stop)
    }

    // MARK: - Engine

    /// Cancels whatever is going on (a travel or a hold)
    private func takeOver() {
        finish(sendStop: false)
    }

    private func seek(to target: Float, coast: Float, timeout: TimeInterval?, done: (() -> Void)?) {
        lastProgress = (currentHeight ?? target, Date())
        mode = .seeking(target: target, coast: coast, deadline: timeout.map { Date().addingTimeInterval($0) }, done: done)
        startPulse()
        evaluateSeek()
    }

    private func startPulse() {
        pulse?.invalidate()
        let timer = Timer(timeInterval: pulseInterval, repeats: true) { [weak self] _ in self?.pulseTick() }
        RunLoop.main.add(timer, forMode: .common)
        pulse = timer
    }

    private func pulseTick() {
        switch mode {
        case .idle:
            pulse?.invalidate()
            pulse = nil
        case .holding(let direction):
            send(direction)
        case .seeking:
            evaluateSeek()
        }
    }

    /// Sends the next command towards the target, or finishes when the target is reached (or the desk stalls)
    private func evaluateSeek() {
        guard case .seeking(let target, let coast, let deadline, let done) = mode, let height = link.height else { return }

        if abs(height - lastProgress.height) > 0.05 {
            lastProgress = (height, Date())
        }

        let remaining = target - height
        let arrived = abs(remaining) <= max(coast, 0.05)
        let timedOut = deadline.map { Date() > $0 } ?? false
        let stalled = direction != .idle && Date().timeIntervalSince(lastProgress.time) > stallTimeout

        if arrived || timedOut || stalled {
            finish(sendStop: true)
            done?()
        } else if abs(remaining) > coast {
            send(remaining > 0 ? .up : .down)
        }
    }

    private func finish(sendStop: Bool) {
        mode = .idle
        pulse?.invalidate()
        pulse = nil
        if sendStop { link.send(.stop) }
        direction = .idle
    }

    private func send(_ direction: TravelDirection) {
        switch direction {
        case .up: link.send(.up)
        case .down: link.send(.down)
        case .idle: return
        }
        self.direction = direction
    }
}
