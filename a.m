#import <Foundation/Foundation.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOMessage.h>
#import <sys/types.h>
#import <sys/wait.h>

static IONotificationPortRef notificationPort;
static io_iterator_t addedIterator;
static io_iterator_t removedIterator;

static int TARGET_VENDOR_ID = 0;
static int TARGET_PRODUCT_ID = 0;
static NSArray *commandArguments = nil;

// Function to check if a USB device matches the target Vendor ID & Product ID
BOOL isTargetDevice(io_service_t usbDevice) {
    CFNumberRef vendorIDRef = IORegistryEntryCreateCFProperty(usbDevice, CFSTR("idVendor"), kCFAllocatorDefault, 0);
    CFNumberRef productIDRef = IORegistryEntryCreateCFProperty(usbDevice, CFSTR("idProduct"), kCFAllocatorDefault, 0);
    
    if (!vendorIDRef || !productIDRef) {
        return NO; // Skip if IDs are missing
    }

    int vendorID, productID;
    CFNumberGetValue(vendorIDRef, kCFNumberIntType, &vendorID);
    CFNumberGetValue(productIDRef, kCFNumberIntType, &productID);
    
    CFRelease(vendorIDRef);
    CFRelease(productIDRef);

    return (vendorID == TARGET_VENDOR_ID && productID == TARGET_PRODUCT_ID);
}

// Function to execute a command with the USB_EVENT environment variable
void runCommand(const char *eventType) {
    if (commandArguments.count == 0) {
        NSLog(@"❌ No command arguments provided.");
        return;
    }

    // Set the USB_EVENT environment variable
    setenv("USB_EVENT", eventType, 1);

    // Prepare the arguments for execvp (first element is the command)
    const char *command = [commandArguments[0] UTF8String];
    char *args[commandArguments.count + 1];

    for (int i = 0; i < commandArguments.count; i++) {
        args[i] = (char *)[commandArguments[i] UTF8String];
    }
    args[commandArguments.count] = NULL; // Null-terminate the argument list

    // Create a new process (fork)
    pid_t pid = fork();
    
    if (pid == -1) {
        // Fork failed
        perror("fork failed");
        return;
    }

    if (pid == 0) {
        // Child process: execute the command
        if (execvp(command, args) == -1) {
            perror("execvp failed");
            exit(1); // Exit child process on failure
        }
    } else {
        // Parent process continues (does not block)
        return;
    }
}

// Callback function for USB attach events
void USBDeviceAttached(void *refcon, io_iterator_t iterator) {
    io_service_t usbDevice;
    while ((usbDevice = IOIteratorNext(iterator))) {
        if (isTargetDevice(usbDevice)) {
            NSLog(@"✅ Target USB device ATTACHED! (Vendor: 0x%X, Product: 0x%X)", TARGET_VENDOR_ID, TARGET_PRODUCT_ID);
            runCommand("attach");
        }
        IOObjectRelease(usbDevice);
    }
}

// Callback function for USB detach events
void USBDeviceDetached(void *refcon, io_iterator_t iterator) {
    io_service_t usbDevice;
    while ((usbDevice = IOIteratorNext(iterator))) {
        if (isTargetDevice(usbDevice)) {
            NSLog(@"❌ Target USB device DETACHED! (Vendor: 0x%X, Product: 0x%X)", TARGET_VENDOR_ID, TARGET_PRODUCT_ID);
            runCommand("detach");
        }
        IOObjectRelease(usbDevice);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Ensure correct number of arguments
        if (argc < 3) {
            NSLog(@"❌ Usage: %s <VendorID> <ProductID> <Command...>", argv[0]);
            NSLog(@"Example: %s 0x1234 0x5678 echo Attached!", argv[0]);
            return 1;
        }

        // Parse Vendor ID and Product ID
        sscanf(argv[1], "%x", &TARGET_VENDOR_ID);
        sscanf(argv[2], "%x", &TARGET_PRODUCT_ID);

        // Store command arguments (excluding VendorID and ProductID)
        NSMutableArray *commandArray = [NSMutableArray array];
        for (int i = 3; i < argc; i++) {
            [commandArray addObject:[NSString stringWithUTF8String:argv[i]]];
        }
        commandArguments = [commandArray copy];
        
        NSLog(@"🎯 Monitoring USB device (Vendor: 0x%X, Product: 0x%X)", TARGET_VENDOR_ID, TARGET_PRODUCT_ID);
        
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

        // Matching dictionary for USB detach events
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

        NSLog(@"🖥️ Listening for Target USB attach & detach events... (Press Ctrl+C to exit)");
        CFRunLoopRun(); // Keep the program running

        // Cleanup (not reached in normal execution)
        IONotificationPortDestroy(notificationPort);
    }
    return 0;
}
