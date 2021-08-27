//
//  PaxDevice.swift
//  PaxDevice
//
//  Created by Tristan Seifert on 20210827.
//

import Foundation
import CoreBluetooth
import OSLog

import CryptoSwift
import CommonCrypto

/**
 * Base class for Pax devices
 */
class PaxDevice: NSObject, CBPeripheralDelegate {
    static let L = Logger(subsystem: "me.tseifert.paxcontrollertest", category: "PaxDevice")
    
    /// Peripheral representing the remote end of the BT LE connection
    private var peripheral: CBPeripheral!
    /// Service handle for the Pax service
    private var paxService: CBService!
    /// Characteristic for reading device state
    private var readCharacteristic: CBCharacteristic!
    /// Characteristic for writing device state
    private var writeCharacteristic: CBCharacteristic!
    /// Service handle for the device info service
    private var infoService: CBService!
    
    /// Encryption key used for encrypting/decrypting packets
    private var deviceKey: Data!
    
    /// Set when the device has been fully initialized and can be used
    @objc private(set) public dynamic var isUsable: Bool = false
    
    /// Device model
    private(set) public var type: DeviceType = .Unknown
    
    /// Serial number of the device, as read during connection establishment
    @objc private(set) public dynamic var serial: String!
    /// Manufacturer of the device
    @objc private(set) public dynamic var manufacturer: String!
    /// Model number of the device
    @objc private(set) public dynamic var model: String!
    /// Hardware revision
    @objc private(set) public dynamic var hwVersion: String!
    /// Software revision
    @objc private(set) public dynamic var swVersion: String!
    
    // MARK: - Initialization
    /**
     * Initializes the Pax device based on a Bluetooth peripheral, which has already been connected to.
     */
    init(_ peripheral: CBPeripheral) {
        super.init()
        
        // scan for the Pax and device info service
        self.peripheral = peripheral
        self.peripheral.delegate = self
        
        self.peripheral.discoverServices([Self.DeviceInfoService, Self.PaxService])
    }
    
    // MARK: - Peripheral delegate
    /**
     * We've discovered services; depending on whether it's the Pax control or device info endpoint, discover the appropriate
     * characteristics.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error {
            Self.L.error("Failed to discover services on \(peripheral): \(String(describing: err))")
            return
        }
        
        // get characeristics of the info service
        guard let infoSvc = peripheral.services?.first(where: { $0.uuid == Self.DeviceInfoService }) else {
            fatalError("Failed to find device info service!")
        }
        self.infoService = infoSvc
        
        peripheral.discoverCharacteristics([Self.ManufacturerCharacteristic,
                                            Self.ModelNumberCharacteristic,
                                            Self.SerialNumberCharacteristic,
                                            Self.HwRevCharacteristic,
                                            Self.SwRevCharacteristic], for: infoSvc)
        
        // get characteristics of the Pax service
        guard let paxSvc = peripheral.services?.first(where: { $0.uuid == Self.PaxService }) else {
            fatalError("Failed to find Pax service!")
        }
        self.paxService = paxSvc
        
        peripheral.discoverCharacteristics([Self.PaxReadCharacteristic,
                                            Self.PaxWriteCharacteristic], for: paxSvc)
    }
    
    /**
     * We've discovered characteristics of a service. We only make requests for characteristics of the Pax and device info service; in
     * the former case, a reference to the appropriate characteristics is stored, whereas for device info, we request reading out all of the
     * known keys once.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error {
            Self.L.error("Failed to discover characteristics on \(peripheral): \(String(describing: err))")
            return
        }
        
        // call the appropriate handler
        let chars = service.characteristics!
        
        if service.uuid == Self.PaxService {
            self.readCharacteristic = chars.first(where: { $0.uuid == Self.PaxReadCharacteristic })
            self.writeCharacteristic = chars.first(where: { $0.uuid == Self.PaxWriteCharacteristic })
            
            guard self.readCharacteristic != nil, self.writeCharacteristic != nil else {
                fatalError("Failed to find a required Pax service characteristic")
            }
            
            // TODO: establish Pax connection
            peripheral.readValue(for: self.readCharacteristic)
        } else if service.uuid == Self.DeviceInfoService {
            // read all discovered values of the info characteristic
            service.characteristics!.forEach {
                peripheral.readValue(for: $0)
            }
        } else {
            Self.L.warning("Got unexpected characteristics for service \(service): \(chars)")
        }
    }
    
    /**
     * Data for the particular characteristic has been read.
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            Self.L.error("Failed to read characteristic \(characteristic): \(String(describing: err))")
            return
        }
        
        // invoke the correct handler
        if characteristic.service == self.infoService {
            if let data = characteristic.value {
                // we have to do this on main thread because KVO
                DispatchQueue.main.async {
                    switch characteristic.uuid {
                        case Self.ManufacturerCharacteristic:
                            self.manufacturer = String(bytes: data, encoding: .utf8)
                        case Self.ModelNumberCharacteristic:
                            self.model = String(bytes: data, encoding: .utf8)
                        case Self.SerialNumberCharacteristic:
                            self.serial = String(bytes: data, encoding: .utf8)
                            self.deriveSharedKey()
                            
                        case Self.HwRevCharacteristic:
                            self.hwVersion = String(bytes: data, encoding: .utf8)
                        case Self.SwRevCharacteristic:
                            self.swVersion = String(bytes: data, encoding: .utf8)
                            
                        default:
                            Self.L.trace("Unexpected device info update for \(characteristic.uuid): \(data.hexEncodedString())")
                    }
                }
            }
        }
        // funnel all Pax service reads through the decoding logic
        else if characteristic.service == self.paxService {
            if let data = characteristic.value {
                self.receivedPaxCharacteristic(data)
            }
        }
        // no handler available
        else {
            if let data = characteristic.value {
                Self.L.trace("Received unexpected characteristic update for \(characteristic): \(data.hexEncodedString())")
            } else {
                Self.L.trace("Received unexpected characteristic update for \(characteristic)")
            }
        }
    }
    
    // MARK: - Pax protocol logic
    /**
     * Derives the shared device key. This is the serial number (8 characters long) repeated twice to form a 16 byte value, which is then
     * encrypted with AES in ECB mode with a fixed key.
     */
    private func deriveSharedKey() {
        // get the key data
        let serialStr = self.serial.appending(self.serial)
        guard let serialData = serialStr.data(using: .utf8) else {
            fatalError("Failed to encode serial string")
        }
        
        // encrypt
        do {
            let cipher = try AES(key: Self.DeviceKeyKey!.bytes, blockMode: ECB(), padding: .noPadding)
            
            let keyData = try cipher.encrypt(serialData.bytes)
            self.deviceKey = Data(keyData)
            
            Self.L.trace("Device key is \(self.deviceKey.hexEncodedString())")
        } catch {
            Self.L.critical("Failed to derive device key: \(error.localizedDescription)")
        }
    }
    
    /**
     * Decrypts a packet received from the device.
     *
     * - parameter packetData Full encrypted packet as read from the Pax service endpoint
     * - returns Decrypted packet data, minus IV and any other headers/footers
     * - throws If packet could not be decrypted successfully
     *
     * The last 16 bytes of the packet are always treated as the IV to use for decrypting that packet; the device shared key is used.
     */
    private func decryptPacket(_ packetData: Data) throws -> Data {
        // split data into IV and actual data and prepare output buffer
        let data = packetData.prefix(upTo: packetData.count - Self.IvLength)
        let iv = packetData.suffix(Self.IvLength)
        
        Self.L.trace("Decrypting message data '\(data.hexEncodedString())' and IV '\(iv.hexEncodedString())'")
        
        // create the cipher and decrypt
        let cipher = try AES(key: self.deviceKey.bytes, blockMode: OFB(iv: iv.bytes),
                             padding: .noPadding)
        let decryptedData = try cipher.decrypt(data.bytes)
        
        return Data(decryptedData)
    }
    
    /**
     * Interprets a received characteristic read from the Pax service.
     */
    private func receivedPaxCharacteristic(_ data: Data) {
        Self.L.trace("Read Pax service value: \(data.hexEncodedString())")
        
        do {
            let decrypted = try self.decryptPacket(data)
            Self.L.trace("Decrypted packet: \(decrypted.hexEncodedString())")
        } catch {
            Self.L.critical("Failed to decode message: \(error.localizedDescription) (message was \(data.hexEncodedString())")
        }
    }
    
    // MARK: - Types and constants
    /**
     * Defines the type of device we're dealing with. This is determined on connection based off the model name string.
     */
    enum DeviceType {
        /// Unable to determine the type of device
        case Unknown
        /// Pax Era device (concentrate)
        case PaxEra
        /// Pax 3 device (crystal fuckin weed)
        case Pax3
    }
    
    /**
     * Defines the various errors that may occur during communication with the device.
     */
    enum Errors: Error {
        /// Failed to decrypt a packet from the device.
        case decryptPacketFailed(_ ccError: Int32)
    }
    
    private static let DeviceInfoService = CBUUID(string: "180A")
    private static let ModelNumberCharacteristic = CBUUID(string: "2A24")
    private static let SerialNumberCharacteristic = CBUUID(string: "2A25")
    private static let SwRevCharacteristic = CBUUID(string: "2A26")
    private static let HwRevCharacteristic = CBUUID(string: "2A27")
    private static let ManufacturerCharacteristic = CBUUID(string: "2A29")
    
    // all control of the Pax devices happens through this service
    private static let PaxService = CBUUID(string: "8E320200-64D2-11E6-BDF4-0800200C9A66")
    private static let PaxReadCharacteristic = CBUUID(string: "8E320201-64D2-11E6-BDF4-0800200C9A66")
    private static let PaxWriteCharacteristic = CBUUID(string: "8E320202-64D2-11E6-BDF4-0800200C9A66")
    
    // Encryption key used for deriving the device key
    private static let DeviceKeyKey = Data(base64Encoded: "98hmw494dTCGKTvVfdMlQA==")
    // Length of the IV appended to all packets, in bytes
    private static let IvLength = 16
}
