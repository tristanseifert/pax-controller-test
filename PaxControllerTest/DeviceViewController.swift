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
    @objc dynamic private(set) internal var device: PaxDevice!
    
    /// subscribers
    private var cancelables: [AnyCancellable] = []
    
    // central that the peripheral belongs to
    weak internal var central: CBCentralManager!
    // the peripheral we are operating on
    @objc dynamic internal var peripheral: CBPeripheral! {
        didSet {
            self.cancelables.removeAll()
            
            if self.peripheral != nil {
                DispatchQueue.main.async {
                    self.loadCount += 1
                }
                
                self.device = PaxDevice(self.peripheral)
                
                let c1 = self.device.$supportedAttributes.sink() { [weak self] attrs in
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
                }
                self.cancelables.append(c1)
                
                self.device.start()
            } else {
                self.device = nil
            }
        }
    }
    
    /// Comma separated list of supported attributes
    @objc dynamic private(set) internal var supportedAttributes: String = ""

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
        self.device.stop()
        
        self.dismiss(sender)
        self.device = nil
    }
}
