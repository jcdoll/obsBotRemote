import Foundation
import IOKit

public struct USBDevice: Equatable, Sendable {
  public var vendorID: UInt16?
  public var productID: UInt16?
  public var locationID: UInt32?
  public var productName: String?
  public var vendorName: String?

  public init(
    vendorID: UInt16?,
    productID: UInt16?,
    locationID: UInt32?,
    productName: String?,
    vendorName: String?
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.locationID = locationID
    self.productName = productName
    self.vendorName = vendorName
  }
}

public final class USBDeviceDiscovery {
  public init() {}

  public func listDevices() -> [USBDevice] {
    #if os(macOS)
      guard let matching = IOServiceMatching("IOUSBHostDevice") else {
        return []
      }

      var iterator: io_iterator_t = 0
      let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
      guard result == KERN_SUCCESS else {
        return []
      }
      defer { IOObjectRelease(iterator) }

      var devices: [USBDevice] = []
      while true {
        let service = IOIteratorNext(iterator)
        if service == 0 {
          break
        }
        devices.append(device(from: service))
        IOObjectRelease(service)
      }

      return devices.sorted { lhs, rhs in
        (lhs.productName ?? "") < (rhs.productName ?? "")
      }
    #else
      return []
    #endif
  }

  private func device(from service: io_service_t) -> USBDevice {
    USBDevice(
      vendorID: uint16Property(service, keys: ["idVendor", "vendor-id"]),
      productID: uint16Property(service, keys: ["idProduct", "product-id"]),
      locationID: uint32Property(service, keys: ["locationID", "locationId"]),
      productName: stringProperty(service, keys: ["USB Product Name", "Product Name"]),
      vendorName: stringProperty(service, keys: ["USB Vendor Name", "Vendor Name"])
    )
  }

  private func stringProperty(_ service: io_service_t, keys: [String]) -> String? {
    for key in keys {
      if let value = registryProperty(service, key: key) as? String {
        return value
      }
    }
    return nil
  }

  private func uint16Property(_ service: io_service_t, keys: [String]) -> UInt16? {
    uint32Property(service, keys: keys).flatMap { UInt16(exactly: $0) }
  }

  private func uint32Property(_ service: io_service_t, keys: [String]) -> UInt32? {
    for key in keys {
      if let value = registryProperty(service, key: key) as? NSNumber {
        return value.uint32Value
      }
      if let value = registryProperty(service, key: key) as? Data {
        return littleEndianInteger(from: value)
      }
    }
    return nil
  }

  private func registryProperty(_ service: io_service_t, key: String) -> Any? {
    IORegistryEntryCreateCFProperty(
      service,
      key as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue()
  }

  private func littleEndianInteger(from data: Data) -> UInt32? {
    guard !data.isEmpty, data.count <= 4 else {
      return nil
    }
    var value: UInt32 = 0
    for (index, byte) in data.enumerated() {
      value |= UInt32(byte) << UInt32(index * 8)
    }
    return value
  }
}
