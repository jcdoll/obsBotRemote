#ifndef OBSBOT_REMOTE_USB_BRIDGE_H
#define OBSBOT_REMOTE_USB_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

int32_t ORUSBGetConfigurationDescriptor(
    uint16_t vendorID,
    uint16_t productID,
    uint8_t configIndex,
    uint8_t *buffer,
    size_t capacity,
    size_t *outLength
);

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
);

#endif
