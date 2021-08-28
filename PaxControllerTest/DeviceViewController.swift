//
//  DeviceViewController.swift
//  DeviceViewController
//
//  Created by Tristan Seifert on 20210826.
//

import Cocoa
import CoreBluetooth
import OSLog
import Combine

class DeviceViewController: NSViewController, CBPeripheralDelegate {
    static let L = Logger(subsystem: "me.tseifert.paxcontrollertest", category: "PaxDeviceController")
    
    // set when we're communicating with the device
    @objc dynamic var isLoading = false
    private var loadCount: Int = 0 {
        didSet {
            self.isLoading = (self.loadCount > 0)
        }
    }
    
    /// Pax device we're dealing with
    @objc dynamic internal var device: PaxDevice! {
        didSet {
            self.cancelables.removeAll()
            
            guard self.device != nil else {
                return
            }
            
            // start loader
            DispatchQueue.main.async {
                self.loadCount += 1
            }
            
            // observe supported attributes
            self.installDeviceObservers(self.device)
            
            // start device
            self.device.start()
        }
    }
    
    /// subscribers
    internal var cancelables: [AnyCancellable] = []
    
    // central that the peripheral belongs to
    weak internal var central: CBCentralManager!
    // the peripheral we are operating on
    @objc dynamic internal var peripheral: CBPeripheral!
    
    /// Comma separated list of supported attributes
    @objc dynamic private(set) internal var supportedAttributes: String = ""
    @objc dynamic private(set) internal var chargeLevel: UInt = 0
    @objc dynamic private(set) internal var chargeState: String!

    /**
     * Fetch some device information on appearance
     */
    override func viewWillAppear() {
        super.viewWillAppear()
    }
    
    /**
     * Install observers on a new device.
     */
    internal func installDeviceObservers(_ device: PaxDevice) {
        self.cancelables.append(device.$supportedAttributes.sink() { [weak self] attrs in
            var str = ""
            attrs.forEach {
                str.append(contentsOf: ", \($0)")
            }
            
            DispatchQueue.main.async {
                if str.isEmpty {
                    self?.supportedAttributes = ""
                } else {
                    self?.supportedAttributes = String(str[String.Index(utf16Offset: 2, in: str)...])
                }
            }
        })
        
        self.cancelables.append(device.$batteryLevel.sink() { [weak self] level in
            DispatchQueue.main.async { self?.chargeLevel = level }
        })
        self.cancelables.append(device.$chargeState.sink() { [weak self] state in
            switch state {
                case .notCharging:
                    DispatchQueue.main.async { self?.chargeState = "Discharging" }
                case .charging:
                    DispatchQueue.main.async { self?.chargeState = "Charging" }
                case .chargingCompleted:
                    DispatchQueue.main.async { self?.chargeState = "Charging Complete" }
                default:
                    DispatchQueue.main.async { self?.chargeState = nil }
            }
        })
    }
    
    /**
     * Disconnect from the device and dismiss the view controller.
     */
    @IBAction func disconnect(_ sender: Any?) {
        self.device.stop()
        
        self.dismiss(sender)
        self.device = nil
    }
}
