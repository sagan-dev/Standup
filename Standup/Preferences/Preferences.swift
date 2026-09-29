//
//  Preferences.swift
//  Standup
//
//  User settings, stored in UserDefaults.
//

import Foundation
import LaunchAtLogin

/// A height the desk can be sent to
enum DeskTarget {
    case sit
    case stand
    case height(Float)
}

final class Preferences {

    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case standingHeight, sittingHeight, heightCalibration, usesMetricUnits, hasRunBefore
    }

    private init() {}

    private func read<T>(_ key: Key, default fallback: T) -> T {
        return defaults.object(forKey: "standup.\(key.rawValue)") as? T ?? fallback
    }

    private func write(_ key: Key, _ value: Any) {
        defaults.set(value, forKey: "standup.\(key.rawValue)")
    }

    // MARK: - Heights (centimetres)

    var standingHeight: Float {
        get { read(.standingHeight, default: 110) }
        set { write(.standingHeight, newValue) }
    }

    var sittingHeight: Float {
        get { read(.sittingHeight, default: 70) }
        set { write(.sittingHeight, newValue) }
    }

    /// Correction the user applies when the displayed height does not match a measurement
    var heightCalibration: Float {
        get { read(.heightCalibration, default: 0) }
        set { write(.heightCalibration, newValue) }
    }

    var usesMetricUnits: Bool {
        get { read(.usesMetricUnits, default: NSLocale.current.usesMetricSystem) }
        set { write(.usesMetricUnits, newValue) }
    }

    var unitName: String {
        return usesMetricUnits ? "cm" : "in"
    }

    func height(for target: DeskTarget) -> Float {
        switch target {
        case .sit: return sittingHeight
        case .stand: return standingHeight
        case .height(let value): return value
        }
    }

    // MARK: - App

    var launchAtLogin: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.isEnabled = newValue }
    }

    var isFirstRun: Bool {
        get { !read(.hasRunBefore, default: false) }
        set { write(.hasRunBefore, !newValue) }
    }
}
