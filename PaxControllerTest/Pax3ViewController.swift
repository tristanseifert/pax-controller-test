//
//  Pax3ViewController.swift
//  Pax3ViewController
//
//  Created by Tristan Seifert on 20210827.
//

import Cocoa

class Pax3ViewController: DeviceViewController {
    @objc dynamic private(set) public var ovenTemp: Float = Float.nan
    @objc dynamic private(set) public var ovenTargetTemp: Float = Float.nan
    @objc dynamic private(set) public var ovenSetTemp: Float = Float.nan
    @objc dynamic private(set) public var heaterState: String!
    @objc dynamic private(set) public var dynamicMode: String!
    
    @objc dynamic public var heatingModeSet: UInt = 0
    @objc dynamic public var tempSet: Float = 175
    
    /**
     * Install observers for temp, heater state, and dynamic mode.
     */
    override func installDeviceObservers(_ inDevice: PaxDevice) {
        guard let device = inDevice as? Pax3Device else {
            fatalError()
        }
        
        super.installDeviceObservers(device)
        
        self.cancelables.append(device.$ovenTemp.sink() { [weak self] temp in
            DispatchQueue.main.async { self?.ovenTemp = temp }
        })
        self.cancelables.append(device.$ovenTargetTemp.sink() { [weak self] temp in
            DispatchQueue.main.async { self?.ovenTargetTemp = temp }
        })
        self.cancelables.append(device.$ovenSetTemp.sink() { [weak self] temp in
            DispatchQueue.main.async { self?.ovenSetTemp = temp }
        })
        
        self.cancelables.append(device.$heatingState.sink() { [weak self] state in
            switch state {
                case .ovenOff:
                    DispatchQueue.main.async { self?.heaterState = "Oven Off" }
                case .boosting:
                    DispatchQueue.main.async { self?.heaterState = "Boosting" }
                case .cooling:
                    DispatchQueue.main.async { self?.heaterState = "Cooling" }
                case .heating:
                    DispatchQueue.main.async { self?.heaterState = "Heating" }
                case .ready:
                    DispatchQueue.main.async { self?.heaterState = "Ready" }
                case .standby:
                    DispatchQueue.main.async { self?.heaterState = "Standby" }
                case .tempSetMode:
                    DispatchQueue.main.async { self?.heaterState = "Temp Set Mode" }
            }
        })

        self.cancelables.append(device.$ovenDynamicMode.sink() { [weak self] state in
            DispatchQueue.main.async {
                self?.heatingModeSet = UInt(state.rawValue)
            }
            switch state {
                case .standard:
                    DispatchQueue.main.async { self?.dynamicMode = "Standard" }
                case .boost:
                    DispatchQueue.main.async { self?.dynamicMode = "Boost" }
                case .efficiency:
                    DispatchQueue.main.async { self?.dynamicMode = "Efficiency" }
                case .stealth:
                    DispatchQueue.main.async { self?.dynamicMode = "Stealth" }
                case .flavor:
                    DispatchQueue.main.async { self?.dynamicMode = "Flavor" }
            }
        })
    }
    
    /**
     * Action to set the device heating mode
     */
    @IBAction func setHeatingMode(_ sender: Any) {
        guard let mode = DynamicModeMessage.Mode(rawValue: UInt8(self.heatingModeSet)) else {
            fatalError("Invalid dynamic mode tag")
        }
        
        do {
            try (self.device as! Pax3Device).setOvenDynamicMode(mode)
        } catch {
            Self.L.error("Failed to set heating mode: \(error.localizedDescription)")
            NSApp.presentError(error, modalFor: self.view.window!, delegate: nil,
                               didPresent: nil, contextInfo: nil)
        }
    }
    
    /**
     * Action to set the temperature
     */
    @IBAction func setTemperature(_ sender: Any) {
        do {
            try (self.device as! Pax3Device).setOvenTemp(self.tempSet)
        } catch {
            Self.L.error("Failed to set oven temp: \(error.localizedDescription)")
            NSApp.presentError(error, modalFor: self.view.window!, delegate: nil,
                               didPresent: nil, contextInfo: nil)
        }
    }
}
