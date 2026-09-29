//
//  DeskLink.swift
//  Standup
//
//  A GATT session with one desk: publishes its height and sends movement commands.
//

import Foundation
import CoreBluetooth

final class DeskLink: NSObject {

    /// Movement commands understood by the desk's control point
    enum Command {
        case up, down, stop

        fileprivate var payload: Data {
            switch self {
            case .up: return Data([0x47, 0x00])
            case .down: return Data([0x46, 0x00])
            case .stop: return Data([0xFF, 0x00])
            }
        }
    }

    // Identifiers of the desk's Bluetooth services (public protocol constants)
    private enum Identifier {
        static let heightService = CBUUID(string: "99FA0020-338A-1024-8A49-009C0215F78A")
        static let heightReport = CBUUID(string: "99FA0021-338A-1024-8A49-009C0215F78A")
        static let controlService = CBUUID(string: "99FA0001-338A-1024-8A49-009C0215F78A")
        static let controlPoint = CBUUID(string: "99FA0002-338A-1024-8A49-009C0215F78A")
    }

    /// The desk reports its height above the lowest position, in hundredths of a centimetre
    private static let lowestHeight: Float = 61.5

    let peripheral: CBPeripheral

    private var heightReport: CBCharacteristic?
    private var controlPoint: CBCharacteristic?

    /// Current height in cm, once the desk has reported it
    private(set) var height: Float?

    /// Signed travel speed reported by the desk; the sign is the direction
    private(set) var velocity: Int16 = 0

    var onHeightChange: ((Float) -> Void)?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
        peripheral.discoverServices([Identifier.heightService, Identifier.controlService])
    }

    func send(_ command: Command) {
        guard let controlPoint = controlPoint else { return }
        peripheral.writeValue(command.payload, for: controlPoint, type: .withResponse)
    }

    private func decodeHeightReport(_ data: Data) {
        guard data.count >= 4 else { return }

        let rawHeight = UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
        let rawVelocity = UInt16(data[data.startIndex + 2]) | (UInt16(data[data.startIndex + 3]) << 8)

        velocity = Int16(bitPattern: rawVelocity)
        let newHeight = Float(rawHeight) / 100 + DeskLink.lowestHeight
        height = newHeight
        onHeightChange?(newHeight)
    }
}

extension DeskLink: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Identifier.heightReport:
                heightReport = characteristic
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            case Identifier.controlPoint:
                controlPoint = characteristic
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Identifier.heightReport, let data = characteristic.value else { return }
        decodeHeightReport(data)
    }
}
