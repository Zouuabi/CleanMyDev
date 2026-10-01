#ifndef CHIDSensors_h
#define CHIDSensors_h

#include <CoreFoundation/CoreFoundation.h>

/// Reads every IOHID sensor of the given page/usage and returns a dictionary
/// of sensor name → value. Temperature sensors on Apple Silicon live on
/// page 0xff00 / usage 5, event type 15. Based on Stats (MIT) and
/// MenuMeters' Apple Silicon reader.
CFDictionaryRef CHIDSensorsCopyValues(int32_t page, int32_t usage, int32_t eventType);

#endif
