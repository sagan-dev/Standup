//
//  ScriptCommands.swift
//  Standup
//
//  AppleScript commands, declared in standup.sdef:
//
//      tell application "Standup" to move desk "stand"
//      tell application "Standup" to set desk height "120cm"
//

import Cocoa

@objc(StandupMoveDeskCommand)
final class MoveDeskCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        guard let driver = DeskDriver.shared else {
            return fail("The desk is not connected.")
        }

        let word = (directParameter as? String)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""

        switch word {
        case "sit": driver.go(to: .sit)
        case "stand": driver.go(to: .stand)
        case "up": driver.step(.up)
        case "down": driver.step(.down)
        default: return fail("Use \"sit\", \"stand\", \"up\" or \"down\".")
        }

        return word
    }
}

@objc(StandupSetHeightCommand)
final class SetHeightCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        guard let driver = DeskDriver.shared else {
            return fail("The desk is not connected.")
        }
        guard let text = directParameter as? String, let centimeters = SetHeightCommand.parseHeight(text) else {
            return fail("Could not read a height. Try \"120cm\", \"48in\" or \"80\".")
        }
        guard (60...135).contains(centimeters) else {
            return fail("That height is outside the desk's range.")
        }

        driver.go(to: .height(centimeters))
        return String(format: "%.1f cm", centimeters)
    }

    /// "120cm", "48 in", "80" -> centimetres
    static func parseHeight(_ text: String) -> Float? {
        let cleaned = text.lowercased().filter { !$0.isWhitespace }

        if cleaned.hasSuffix("cm"), let value = Float(cleaned.dropLast(2)) {
            return value
        }
        if cleaned.hasSuffix("in"), let value = Float(cleaned.dropLast(2)) {
            return value.inchesToCentimeters
        }
        guard let value = Float(cleaned) else { return nil }
        return Preferences.shared.usesMetricUnits ? value : value.inchesToCentimeters
    }
}

private extension NSScriptCommand {
    func fail(_ message: String) -> Any? {
        scriptErrorNumber = Int(errAEEventFailed)
        scriptErrorString = message
        return nil
    }
}
