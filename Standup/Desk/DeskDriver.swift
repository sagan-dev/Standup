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
    private let burstInterval: TimeInterval = 0.5 // minimum time between commands while approaching a target
    private let burstProgress: Float = 0.5        // minimum progress (cm) since the last command before sending the next
    private let resendAfter: TimeInterval = 1.0   // send again anyway if the desk has not made that progress
    private let defaultRollDistance: Float = 0.8  // how far the desk still rolls after the last command (learned per direction)
    private let arriveTolerance: Float = 0.3

    // MARK: - State

    private enum Mode {
        case idle
        case holding(TravelDirection)
        case seeking(target: Float, coast: Float, deadline: Date?, done: (() -> Void)?)
        /// Travel to a height in bursts: a command only every so often and only after real progress, so the desk never runs away
        case approaching(target: Float, deadline: Date?, done: (() -> Void)?)
    }

    private var mode: Mode = .idle

    /// Bumped whenever something new takes over, so a pending measurement of the roll distance is dropped
    private var epoch = 0
    private var pulse: Timer?
    private var lastProgress = (height: Float(0), time: Date())
    private var lastCommand = Date.distantPast
    private var approachStart: Float = 0

    /// Distance the desk keeps rolling after "stop", measured after every travel and remembered between launches
    private var learnedRoll: [TravelDirection: Float] = [
        .up: UserDefaults.standard.object(forKey: "standup.roll.up") as? Float ?? 0.8,
        .down: UserDefaults.standard.object(forKey: "standup.roll.down") as? Float ?? 0.8
    ]
    private var commandHeight: Float?
    private var heightObservers = [(Float) -> Void]()

    init(link: DeskLink) {
        self.link = link

        link.onHeightChange = { [weak self] height in
            guard let self = self else { return }
            self.evaluateMode()
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
        approach(to: Preferences.shared.height(for: target), timeout: nil, done: nil)
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
        approach(to: current + sign * distance, timeout: 3, done: nil)
    }

    func stop() {
        takeOver()
        link.send(.stop)
    }

    // MARK: - Engine

    /// Cancels whatever is going on (a travel or a hold)
    private func takeOver() {
        epoch += 1
        finish(sendStop: false)
    }

    private func seek(to target: Float, coast: Float, timeout: TimeInterval?, done: (() -> Void)?) {
        lastProgress = (currentHeight ?? target, Date())
        mode = .seeking(target: target, coast: coast, deadline: timeout.map { Date().addingTimeInterval($0) }, done: done)
        startPulse()
        evaluateSeek()
    }

    private func approach(to target: Float, timeout: TimeInterval?, done: (() -> Void)?) {
        lastProgress = (currentHeight ?? target, Date())
        lastCommand = .distantPast
        commandHeight = nil
        approachStart = currentHeight ?? target
        mode = .approaching(target: target, deadline: timeout.map { Date().addingTimeInterval($0) }, done: done)
        startPulse()
        evaluateApproach()
    }

    /// Sends the next burst towards the target, or stops with a margin for the distance the desk still rolls
    private func evaluateApproach() {
        guard case .approaching(let target, let deadline, let done) = mode, let height = link.height else { return }

        let now = Date()
        if abs(height - lastProgress.height) > 0.05 {
            lastProgress = (height, now)
        }

        let remaining = target - height
        let goingUp = remaining > 0
        let travelling: TravelDirection = goingUp ? .up : .down

        // While the desk is being driven it keeps rolling a bit after "stop"
        var expected = height
        let roll = learnedRoll[travelling] ?? defaultRollDistance
        if direction == travelling { expected += goingUp ? roll : -roll }

        let reached = abs(remaining) < arriveTolerance || (goingUp ? expected >= target : expected <= target)
        let timedOut = deadline.map { now > $0 } ?? false
        let stalled = direction != .idle && now.timeIntervalSince(lastProgress.time) > stallTimeout

        if reached || timedOut || stalled {
            // Only a real, undisturbed travel tells how far the desk rolls after "stop"
            if reached && !timedOut && !stalled && deadline == nil && abs(height - approachStart) > 2 {
                scheduleRollCalibration(travelling, stopHeight: height)
            }
            finish(sendStop: true)
            done?()
            return
        }

        let sinceCommand = now.timeIntervalSince(lastCommand)
        let progressed = commandHeight.map { abs(height - $0) >= burstProgress } ?? true
        if (sinceCommand >= burstInterval && progressed) || sinceCommand >= resendAfter {
            send(travelling)
            lastCommand = now
            commandHeight = height
        }
    }

    /// Once the desk has settled, measures how far it rolled past the height at which it was stopped
    private func scheduleRollCalibration(_ travelled: TravelDirection, stopHeight: Float) {
        let session = epoch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.epoch == session, self.direction == .idle, let settled = self.link.height else { return }

            let measured = (settled - stopHeight) * (travelled == .up ? 1 : -1)
            guard measured > -0.5, measured < 3 else { return }

            let previous = self.learnedRoll[travelled] ?? self.defaultRollDistance
            let updated = min(2.5, max(0.2, 0.6 * previous + 0.4 * measured))
            self.learnedRoll[travelled] = updated
            UserDefaults.standard.set(updated, forKey: travelled == .up ? "standup.roll.up" : "standup.roll.down")
        }
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
        case .seeking, .approaching:
            evaluateMode()
        }
    }

    private func evaluateMode() {
        switch mode {
        case .seeking: evaluateSeek()
        case .approaching: evaluateApproach()
        default: break
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
