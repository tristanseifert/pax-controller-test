//
//  DeviceViewController.swift
//  DeviceViewController
//
//  Created by Tristan Seifert on 20210826.
//

import Cocoa
import CoreBluetooth
import OSLog

class DeviceViewController: NSViewController, CBPeripheralDelegate {
    static let L = Logger(subsystem: "me.tseifert.paxcontrollertest", category: "browser")
    
    // set when we're communicating with the device
    @objc dynamic var isLoading = false
    private var loadCount: Int = 0 {
        didSet {
            self.isLoading = (self.loadCount > 0)
        }
    }
    
    static let DeviceInfoService = CBUUID(string: "180A")
    static let ModelNumberCharacteristic = CBUUID(string: "2A24")
    static let SerialNumberCharacteristic = CBUUID(string: "2A25")
    static let SwRevCharacteristic = CBUUID(string: "2A26")
    static let HwRevCharacteristic = CBUUID(string: "2A27")
    static let ManufacturerCharacteristic = CBUUID(string: "2A29")
    
    // Pax control service's identifier
    static let PaxService = CBUUID(string: "8E320200-64D2-11E6-BDF4-0800200C9A66")
    // Read characteristic identifier
    static let PaxReadCharacteristic = CBUUID(string: "8E320201-64D2-11E6-BDF4-0800200C9A66")
    // Write characteristic identifier
    static let PaxWriteCharacteristic = CBUUID(string: "8E320202-64D2-11E6-BDF4-0800200C9A66")
    
    // Service handle for the Pax service
    private var paxService: CBService!
    // Characteristic for reading device state
    private var readCharacteristic: CBCharacteristic!
    // Characteristic for writing device state
    private var writeCharacteristic: CBCharacteristic!

    // Service handle for the device info service
    private var infoService: CBService!
    
    // central that the peripheral belongs to
    weak internal var central: CBCentralManager!
    // the peripheral we are operating on
    @objc dynamic internal var peripheral: CBPeripheral! {
        didSet {
            if self.peripheral != nil {
                self.peripheral.delegate = self
                self.updateDeviceInfo()
            }
        }
    }
    
    @objc dynamic internal var deviceManufacturer: String!
    @objc dynamic internal var deviceModel: String!
    @objc dynamic internal var deviceSerial: String!
    @objc dynamic internal var deviceHwRev: String!
    @objc dynamic internal var deviceSwRev: String!

    /**
     * Fetch some device information on appearance
     */
    override func viewWillAppear() {
        super.viewWillAppear()
    }
    
    /**
     * Fetch device information.
     */
    private func updateDeviceInfo() {
        DispatchQueue.main.async {
            self.loadCount += 1
        }
        
        self.peripheral.discoverServices([Self.DeviceInfoService, Self.PaxService])
    }
    
    /**
     * The device information service has been discovered, so query it for some information about the device.
     */
    private func readDeviceInfo() {
        // read all the values
        DispatchQueue.main.async {
            self.loadCount += 5
        }
        
        self.infoService.characteristics!.forEach {
            self.infoService.peripheral!.readValue(for: $0)
        }
    }
    
    /**
     * Disconnect from the device and dismiss the view controller.
     */
    @IBAction func disconnect(_ sender: Any?) {
        self.peripheral = nil
        self.dismiss(sender)
    }
    
    // MARK: - Peripheral Delegate
    /**
     * We've discovered services; depending on whether it's the Pax control or device info endpoint, discover the appropriate
     * characteristics.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error {
            Self.L.error("Failed to discover services on \(peripheral): \(String(describing: err))")
            return
        }
        
        Self.L.trace("Services: \(peripheral.services!)")
        
        // get characteristics of the Pax service
        guard let paxSvc = peripheral.services?.first(where: { $0.uuid == Self.PaxService }) else {
            fatalError("Failed to find Pax service")
        }
        self.paxService = paxSvc
        
        peripheral.discoverCharacteristics([Self.PaxReadCharacteristic, Self.PaxWriteCharacteristic], for: paxSvc)
        
        // get characeristics of the info service
        guard let infoSvc = peripheral.services?.first(where: { $0.uuid == Self.DeviceInfoService }) else {
            fatalError("Failed to find Pax service")
        }
        self.infoService = infoSvc
        
        peripheral.discoverCharacteristics([Self.ManufacturerCharacteristic,
                                            Self.ModelNumberCharacteristic,
                                            Self.SerialNumberCharacteristic,
                                            Self.HwRevCharacteristic,
                                            Self.SwRevCharacteristic], for: infoSvc)
    }
    
    /**
     * We've discovered characteristics of a service. We only make requests for characteristics of the Pax service. A reference to the
     * read and write characteristics is stored.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error {
            Self.L.error("Failed to discover characteristics on \(peripheral): \(String(describing: err))")
            return
        }
        
        // call the appropriate handler
        let chars = service.characteristics!
        Self.L.trace("Characteristics: \(chars)")
        
        if service.uuid == Self.PaxService {
            self.readCharacteristic = chars.first(where: { $0.uuid == Self.PaxReadCharacteristic })
            self.writeCharacteristic = chars.first(where: { $0.uuid == Self.PaxWriteCharacteristic })
            
            guard self.readCharacteristic != nil, self.writeCharacteristic != nil else {
                fatalError("Failed to find a required Pax service characteristic")
            }
            
            // TODO: establish Pax connection
        } else if service.uuid == Self.DeviceInfoService {
            self.readDeviceInfo()
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
                switch characteristic.uuid {
                    case Self.ManufacturerCharacteristic:
                        self.deviceManufacturer = String(bytes: data, encoding: .utf8)
                    case Self.ModelNumberCharacteristic:
                        self.deviceModel = String(bytes: data, encoding: .utf8)
                    case Self.SerialNumberCharacteristic:
                        self.deviceSerial = String(bytes: data, encoding: .utf8)
                    case Self.HwRevCharacteristic:
                        self.deviceHwRev = String(bytes: data, encoding: .utf8)
                    case Self.SwRevCharacteristic:
                        self.deviceSwRev = String(bytes: data, encoding: .utf8)
                        
                    default:
                        Self.L.trace("Unexpected device info update for \(characteristic.uuid): \(data.hexEncodedString())")
                }
            }
            
            DispatchQueue.main.async {
                self.loadCount -= 1
            }
        }
        else if characteristic.service == self.paxService {
            if let data = characteristic.value {
                Self.L.trace("Read Pax service value \(characteristic.uuid): \(data.hexEncodedString())")
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
}
