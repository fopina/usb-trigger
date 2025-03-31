#import <Foundation/Foundation.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOMessage.h>

static IONotificationPortRef notificationPort;
static io_iterator_t addedIterator;
static io_iterator_t removedIterator;

// Callback function for USB attach events
void USBDeviceAttached(void *refcon, io_iterator_t iterator) {
    io_service_t usbDevice;
    while ((usbDevice = IOIteratorNext(iterator))) {
        NSLog(@"🔌 USB device attached!");
        IOObjectRelease(usbDevice);
    }
}

// Callback function for USB detach events
void USBDeviceDetached(void *refcon, io_iterator_t iterator) {
    io_service_t usbDevice;
    while ((usbDevice = IOIteratorNext(iterator))) {
        NSLog(@"❌ USB device detached!");
        IOObjectRelease(usbDevice);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Create notification port
        mach_port_t masterPort;
        IOMasterPort(MACH_PORT_NULL, &masterPort);
        notificationPort = IONotificationPortCreate(masterPort);
        CFRunLoopSourceRef runLoopSource = IONotificationPortGetRunLoopSource(notificationPort);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);

        // Matching dictionary for USB attach events
        CFMutableDictionaryRef matchingDictAttach = IOServiceMatching(kIOUSBDeviceClassName);
        if (!matchingDictAttach) {
            NSLog(@"❌ Failed to create attach matching dictionary");
            return 1;
        }

        // Register for USB attach events
        kern_return_t kr = IOServiceAddMatchingNotification(
            notificationPort,
            kIOMatchedNotification,
            matchingDictAttach,
            USBDeviceAttached,
            NULL,
            &addedIterator
        );
        if (kr != KERN_SUCCESS) {
            NSLog(@"❌ Failed to register USB attach notification");
            return 1;
        }

        // Process currently attached devices
        USBDeviceAttached(NULL, addedIterator);

        // Matching dictionary for USB detach events (must be separate!)
        CFMutableDictionaryRef matchingDictDetach = IOServiceMatching(kIOUSBDeviceClassName);
        if (!matchingDictDetach) {
            NSLog(@"❌ Failed to create detach matching dictionary");
            return 1;
        }

        // Register for USB detach events
        kr = IOServiceAddMatchingNotification(
            notificationPort,
            kIOTerminatedNotification,
            matchingDictDetach,
            USBDeviceDetached,
            NULL,
            &removedIterator
        );
        if (kr != KERN_SUCCESS) {
            NSLog(@"❌ Failed to register USB detach notification");
            return 1;
        }

        // Process currently removed devices
        USBDeviceDetached(NULL, removedIterator);

        NSLog(@"🖥️ Listening for USB attach & detach events... (Press Ctrl+C to exit)");
        CFRunLoopRun(); // Keep the program running

        // Cleanup (not reached in normal execution)
        IONotificationPortDestroy(notificationPort);
    }
    return 0;
}
