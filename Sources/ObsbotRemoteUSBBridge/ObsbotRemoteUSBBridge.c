#include "ObsbotRemoteUSBBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOReturn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USB.h>
#include <string.h>

static void ORUSBAddIntMatch(CFMutableDictionaryRef dict, const void *key, uint16_t value) {
    int numberValue = value;
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &numberValue);
    if (number == NULL) {
        return;
    }
    CFDictionarySetValue(dict, key, number);
    CFRelease(number);
}

static io_service_t ORUSBFindDeviceWithClass(const char *className, uint16_t vendorID, uint16_t productID) {
    CFMutableDictionaryRef matching = IOServiceMatching(className);
    if (matching == NULL) {
        return IO_OBJECT_NULL;
    }

    ORUSBAddIntMatch(matching, CFSTR(kUSBVendorID), vendorID);
    ORUSBAddIntMatch(matching, CFSTR(kUSBProductID), productID);

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (result != KERN_SUCCESS) {
        return IO_OBJECT_NULL;
    }

    io_service_t service = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    return service;
}

static io_service_t ORUSBFindDevice(uint16_t vendorID, uint16_t productID) {
    io_service_t service = ORUSBFindDeviceWithClass(kIOUSBDeviceClassName, vendorID, productID);
    if (service != IO_OBJECT_NULL) {
        return service;
    }
    return ORUSBFindDeviceWithClass("IOUSBHostDevice", vendorID, productID);
}

static IOReturn ORUSBCreateDeviceInterface(
    uint16_t vendorID,
    uint16_t productID,
    IOUSBDeviceInterface ***outDevice
) {
    if (outDevice == NULL) {
        return kIOReturnBadArgument;
    }
    *outDevice = NULL;

    io_service_t service = ORUSBFindDevice(vendorID, productID);
    if (service == IO_OBJECT_NULL) {
        return kIOReturnNotFound;
    }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn result = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugin,
        &score
    );
    IOObjectRelease(service);
    if (result != kIOReturnSuccess || plugin == NULL) {
        return result == kIOReturnSuccess ? kIOReturnError : result;
    }

    HRESULT queryResult = (*plugin)->QueryInterface(
        plugin,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
        (LPVOID *)outDevice
    );
    (*plugin)->Release(plugin);

    if (queryResult != S_OK || *outDevice == NULL) {
        return kIOReturnUnsupported;
    }
    return kIOReturnSuccess;
}

int32_t ORUSBGetConfigurationDescriptor(
    uint16_t vendorID,
    uint16_t productID,
    uint8_t configIndex,
    uint8_t *buffer,
    size_t capacity,
    size_t *outLength
) {
    if (buffer == NULL || outLength == NULL) {
        return kIOReturnBadArgument;
    }
    *outLength = 0;

    IOUSBDeviceInterface **device = NULL;
    IOReturn result = ORUSBCreateDeviceInterface(vendorID, productID, &device);
    if (result != kIOReturnSuccess) {
        return result;
    }

    IOUSBConfigurationDescriptorPtr descriptor = NULL;
    result = (*device)->GetConfigurationDescriptorPtr(device, configIndex, &descriptor);
    if (result != kIOReturnSuccess || descriptor == NULL) {
        (*device)->Release(device);
        return result == kIOReturnSuccess ? kIOReturnError : result;
    }

    size_t length = descriptor->wTotalLength;
    *outLength = length;
    if (capacity < length) {
        (*device)->Release(device);
        return kIOReturnNoSpace;
    }

    memcpy(buffer, descriptor, length);
    (*device)->Release(device);
    return kIOReturnSuccess;
}

int32_t ORUSBDeviceRequest(
    uint16_t vendorID,
    uint16_t productID,
    uint8_t requestType,
    uint8_t request,
    uint16_t value,
    uint16_t index,
    uint8_t *data,
    uint16_t length,
    uint32_t *bytesTransferred
) {
    if (length > 0 && data == NULL) {
        return kIOReturnBadArgument;
    }
    if (bytesTransferred != NULL) {
        *bytesTransferred = 0;
    }

    IOUSBDeviceInterface **device = NULL;
    IOReturn result = ORUSBCreateDeviceInterface(vendorID, productID, &device);
    if (result != kIOReturnSuccess) {
        return result;
    }

    IOUSBDevRequestTO requestBlock;
    memset(&requestBlock, 0, sizeof(requestBlock));
    requestBlock.bmRequestType = requestType;
    requestBlock.bRequest = request;
    requestBlock.wValue = value;
    requestBlock.wIndex = index;
    requestBlock.wLength = length;
    requestBlock.pData = data;
    requestBlock.noDataTimeout = 1000;
    requestBlock.completionTimeout = 1000;

    result = (*device)->DeviceRequestTO(device, &requestBlock);
    if (result == kIOReturnNotOpen) {
        IOReturn openResult = (*device)->USBDeviceOpen(device);
        if (openResult == kIOReturnSuccess) {
            result = (*device)->DeviceRequestTO(device, &requestBlock);
            (*device)->USBDeviceClose(device);
        }
    }

    if (bytesTransferred != NULL) {
        *bytesTransferred = requestBlock.wLenDone;
    }
    (*device)->Release(device);
    return result;
}
