//
//  PaxMessage.swift
//  PaxMessage
//
//  Contains definitions for messages exchanged between the device.
//
//  Created by Tristan Seifert on 20210827.
//

import Foundation

/**
 * Defines an abstract interface that all Pax device messages should implement.
 */
protocol PaxMessage {
    var type: PaxMessageType { get }
}

/**
 * Messages that can be sent from device to host
 */
protocol PaxDecodableMessage: PaxMessage {
    /**
     * Initialize a message from a decrypted packet.
     */
    init(fromPacket packet: Data) throws
}

/**
 * Messages that are sent from host to device
 */
protocol PaxEncodableMessage: PaxMessage {
    /**
     * Serializes the message into a binary blob ready to send to the device.
     */
    func encode() throws -> Data
}

/**
 * Supported Pax message types
 */
enum PaxMessageType: UInt8, CaseIterable {
    case HeaterSetPoint = 2
    case Battery = 3
    case Usage = 4
    case UsageLimit = 5
    case LockStatus = 6
    case ChargeStatus = 7
    case PodInserted = 8
    case Time = 9
    case DisplayName = 10
    case HeaterRanges = 17
    case DynamicMode = 19
    case ColorTheme = 20
    case Brightness = 21
    case HapticMode = 23
    /// Request to read which attributes are supported by the device
    case SupportedAttributes = 24
    case HeatingParams = 25
    case UiMode = 27
    case ShellColor = 28
    case LowSoCMode = 30
    case CurrentTargetTemp = 31
    case HeatingState = 32
    case Haptics = 40
    /// Requests the device send updates for n properties
    case StatusUpdate = 254
}


// MARK: - Host to device messages
/**
 * The device will send the current value of the requested attributes when received.
 *
 * Note: This message can only be sent to the device; it cannot be received.
 */
class StatusUpdateMessage: PaxMessage, PaxEncodableMessage {
    private(set) public var type: PaxMessageType = .StatusUpdate
    /// Attributes to request from the device
    private(set) public var attributes: Set<PaxMessageType> = []
    
    /**
     * Allocate a new status update message requesting the attributes corresponding to the provided message types.
     */
    init(attributes: Set<PaxMessageType>) {
        self.attributes = attributes
    }
    
    /**
     * Encode the status update message.
     *
     * Its only payload is a 64-bit integer that follows the type. This is treated like a bitmask; bit n corresponds to the attribute that is read
     * out by a message of type n. For example, the battery message type is 3, so (1 << 3) would be set to read this out.
     */
    func encode() throws -> Data {
        var data = Data(count: 16)
        data[0] = self.type.rawValue
        
        // build up the bit field
        var field: UInt64 = 0
        
        try self.attributes.forEach { attr in
            // we can only handle attributes with a value of 64 and under
            guard attr.rawValue <= 63 else {
                throw Errors.unsupportedAttribute(attr)
            }
            
            field |= (UInt64(1) << UInt64(attr.rawValue))
        }
        
        // store it (yuck)
        data.withUnsafeMutableBytes { dataBytes in
            var value = field.littleEndian
            let valueData = Data(bytes: &value, count: MemoryLayout<UInt64>.size)
            
            valueData.withUnsafeBytes { valueBytes in
                let offset = UnsafeMutableRawBufferPointer(rebasing: dataBytes[1..<9])
                offset.copyBytes(from: valueBytes)
            }
        }
        
        return data
    }
    
    enum Errors: Error {
        /// This attribute is not supported in status updates.
        case unsupportedAttribute(_ attribute: PaxMessageType)
    }
}

// MARK: - Device to host messages
/**
 * Indicates which attributes are supported by the device.
 *
 * The only payload is a 64-bit bitmask that is encoded identically to the status request message.
 */
class SupportedAttributesMessage: PaxMessage, PaxDecodableMessage {
    private(set) public var type: PaxMessageType = .SupportedAttributes
    /// Attributes supported by the device
    private(set) public var attributes: Set<PaxMessageType> = []
    
    /**
     * Attempt to decode the message.
     */
    required init(fromPacket packet: Data) throws {
        precondition(packet[0] == self.type.rawValue)
        guard packet.count > (1 + 8) else {
            throw Errors.invalidSize
        }
        
        // read out the bitmask and check if it matches any message IDs
        let mask: UInt64 = packet.readEndian(1, .little)
        
        PaxMessageType.allCases.forEach {
            guard $0.rawValue <= 63 else {
                return
            }
            if (mask & (1 << UInt64($0.rawValue))) != 0 {
                self.attributes.insert($0)
            }
        }
    }
    
    enum Errors: Error {
        /// Message is too small
        case invalidSize
    }
}
