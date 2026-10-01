#include "CHIDSensors.h"
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef double IOHIDFloat;

#define IOHIDEventFieldBase(type) (type << 16)

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
extern IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

CFDictionaryRef CHIDSensorsCopyValues(int32_t page, int32_t usage, int32_t eventType) {
    CFMutableDictionaryRef out = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return out;

    CFNumberRef pageN = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &page);
    CFNumberRef usageN = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usage);
    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *vals[] = { pageN, usageN };
    CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(client, matching);
    CFRelease(matching); CFRelease(pageN); CFRelease(usageN);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services) {
        CFIndex n = CFArrayGetCount(services);
        for (CFIndex i = 0; i < n; i++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
            CFStringRef name = (CFStringRef)IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
            IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, eventType, 0, 0);
            if (name && event) {
                double value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(eventType));
                CFNumberRef v = CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &value);
                CFDictionarySetValue(out, name, v);
                CFRelease(v);
            }
            if (event) CFRelease(event);
            if (name) CFRelease(name);
        }
        CFRelease(services);
    }
    CFRelease(client);
    return out;
}
