//
//  ViewController.swift
//  PaxControllerTest
//
//  Created by Tristan Seifert on 20210826.
//

import Cocoa
import CoreBluetooth
import OSLog

class DeviceBrowserViewController: NSViewController, CBCentralManagerDelegate {
    static let L = Logger(subsystem: "me.tseifert.paxcontrollertest", category: "browser")
    
    /// set when we're actively scanning for devices
    @objc dynamic var isScanning: Bool = false
    /// set when we're connecting to a device
    @objc dynamic var isConnecting: Bool = false
    /// devices we've found during scanning
    @objc dynamic var devices: [[String: Any]] = []

    @IBOutlet var arrayMan: NSArrayController!
    
    private var btQueue = DispatchQueue(label: "Bluetooth", qos: .userInitiated, attributes: [], autoreleaseFrequency: .inherit)
    private var central: CBCentralManager!
    
    // peripheral we're pending to connect to
    private var connectTo: CBPeripheral? = nil
    // determine the type of device we are connecting to
    private lazy var probulator = PaxDeviceProber()
    
    /**
     * Sets up the central that we use later to browse for services
     */
    override func viewDidLoad() {
        super.viewDidLoad()

        // create the central
        self.central = CBCentralManager(delegate: self, queue: self.btQueue, options: nil)
    }
    
    /**
     * Start scanning for devices on appearance
     */
    override func viewDidAppear() {
        if !self.isScanning {
            self.startScanning(nil)
        }
    }

    // MARK: - Actions for browsing
    /**
     * Begins searching for devices.
     */
    @IBAction func startScanning(_ sender: Any?) {
        precondition(!self.isScanning, "we are already scanning!")
        
        self.devices.removeAll()
        self.isScanning = true
        
        self.central.scanForPeripherals(withServices: [CBUUID(string: "8E320200-64D2-11E6-BDF4-0800200C9A66")], options: nil)
    }
    
    /**
     * Stop scanning for devices.
     */
    @IBAction func stopScanning(_ sender: Any?) {
        precondition(self.isScanning, "we are not scanning!")
        
        self.central.stopScan()
        self.isScanning = false
    }
    
    /**
     * Connect that shit
     */
    @IBAction func connect(_ sender: Any?) {
        guard let info = self.arrayMan.selectedObjects?.first as? [String: Any?],
              let peripheral = info["peripheral"] as? CBPeripheral else {
            fatalError("you should select something")
        }
        if self.isScanning {
            self.stopScanning(sender)
        }
        
        Self.L.info("Connecting to peripheral \(info)")
        
        // connect pls
        self.central.connect(peripheral, options: nil)
    }
    
    // MARK: - Central delegate
    /**
     * Handles central state changes.
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Self.L.info("Central state changed: \(central.state.rawValue)")
    }
    
    /**
     * We've discovered a device.
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Self.L.trace("Discovered peripheral \(peripheral) (RSSI \(RSSI)); advertisement data \(advertisementData)")
        
        DispatchQueue.main.async {
            self.devices.append(["rssi": RSSI,
                                 "identifier": peripheral.identifier,
                                 "name": peripheral.name ?? "(unknown)",
                                 "peripheral": peripheral])
        }
    }
    
    /**
     * Successfully connected to a peripheral
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Self.L.debug("Connected to peripheral \(peripheral); probing...")
        
        DispatchQueue.main.async {
            self.isConnecting = true
        }
        
        // and probe it
        self.probulator.probe(peripheral) { res in
            switch res {
                case .success(let device):
                    switch device.type {
                        case .Pax3:
                            DispatchQueue.main.async {
                                let sb = self.storyboard
                                let vc = sb!.instantiateController(withIdentifier: "pax3DeviceController") as! DeviceViewController
                                
                                vc.central = central
                                vc.peripheral = peripheral
                                vc.device = device
                                
                                self.presentAsSheet(vc)
                            }
                            
                        default:
                            Self.L.error("No device VC for type \(String(describing: device.type))")
                    }
                    
                case .failure(let err):
                    Self.L.error("Failed to probe device: \(err.localizedDescription)")
                    DispatchQueue.main.async {
                        NSApp.presentError(err)
                    }
            }
            
            DispatchQueue.main.async {
                self.isConnecting = false
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // TODO: try to reconnect
        Self.L.warning("Disconnected PaxDevice \(peripheral)")
    }
    
    /**
     * Failed to connect to a peripheral.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.connectTo = nil
        
        // log error info
        Self.L.error("Failed to connect to \(peripheral): \(String(describing: error))")
        if let err = error {
            NSApp.presentError(err)
        }
    }
}

