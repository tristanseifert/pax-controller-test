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
    
    /// Pax device we're dealing with
    @objc dynamic private(set) internal var device: PaxDevice!
    
    // central that the peripheral belongs to
    weak internal var central: CBCentralManager!
    // the peripheral we are operating on
    @objc dynamic internal var peripheral: CBPeripheral! {
        didSet {
            if self.peripheral != nil {
                DispatchQueue.main.async {
                    self.loadCount += 1
                }
                self.device = PaxDevice(self.peripheral)
            } else {
                self.device = nil
            }
        }
    }

    /**
     * Fetch some device information on appearance
     */
    override func viewWillAppear() {
        super.viewWillAppear()
    }
    
    /**
     * Disconnect from the device and dismiss the view controller.
     */
    @IBAction func disconnect(_ sender: Any?) {
        self.dismiss(sender)
        self.device = nil
    }
}
