//
//  DeskScanner.swift
//  Standup
//
//  Finds the desk over Bluetooth, connects to it and keeps the connection alive.
//

import Foundation
import CoreBluetooth

final class DeskScanner: NSObject {

    static let shared = DeskScanner()

    /// The desk we are connected to (or connecting to)
    private(set) var desk: CBPeripheral?

    private(set) var central: CBCentralManager?

    /// Called on the main queue whenever the Bluetooth radio state or authorization changes
    var onBluetoothStateChange: (() -> Void)?

    /// Called on the main queue when a desk connects (with it) or disconnects (with nil)
    var onDeskChange: ((CBPeripheral?) -> Void)?

    /// The last desk we were connected to, used to reconnect after a drop
    private var lastDesk: CBPeripheral?

    private override init() {
        super.init()
    }

    /// Starts Bluetooth (and asks for permission on first use). Safe to call repeatedly.
    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if desk == nil {
            beginScan()
        }
    }

    /// Reconnects to a desk that dropped, e.g. after the Mac woke up
    func reconnectIfNeeded() {
        guard let central = central, central.state == .poweredOn else { return }

        if let known = desk ?? lastDesk, known.state == .disconnected {
            central.connect(known)
        }
    }

    private func beginScan() {
        guard let central = central, central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(withServices: nil)
    }

    private func looksLikeDesk(_ peripheral: CBPeripheral) -> Bool {
        return peripheral.name?.contains("Desk") == true
    }
}

extension DeskScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onBluetoothStateChange?()

        guard central.state == .poweredOn else { return }

        if let known = desk ?? lastDesk {
            central.connect(known)
        } else {
            beginScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard desk == nil, looksLikeDesk(peripheral) else { return }

        // First desk in range wins; keep a reference so the connection is not dropped
        desk = peripheral
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Either the desk we picked, or the one we asked to reconnect to after a drop
        guard peripheral == desk || peripheral == lastDesk else { return }

        desk = peripheral
        central.stopScan()
        lastDesk = peripheral
        onDeskChange?(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == desk else { return }

        desk = nil
        onDeskChange?(nil)

        // Look for it again; a pending connect completes as soon as the desk is back in range
        central.connect(peripheral)
        beginScan()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == desk || peripheral == lastDesk else { return }

        desk = nil
        onDeskChange?(nil)
        beginScan()
    }
}
