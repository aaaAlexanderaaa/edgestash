#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>

typedef int (*ESMainConnectionIDFunction)(void);
typedef uint64_t (*ESCurrentSpaceFunction)(int, CFStringRef);
typedef CFArrayRef (*ESCopySpacesForWindowsFunction)(int, int, CFArrayRef);
typedef int (*ESSpaceTypeFunction)(int, uint64_t);

@interface NSObject (EdgeStashDisplaySpaceOperation)
- (instancetype)initWithWindows:(NSArray<NSNumber *> *)windows spaceID:(uint64_t)spaceID;
- (void)performWithWMBridgeDelegate;
@end

static ESMainConnectionIDFunction mainConnectionFunction;
static ESCurrentSpaceFunction currentSpaceFunction;
static ESCopySpacesForWindowsFunction copySpacesForWindowsFunction;
static ESSpaceTypeFunction spaceTypeFunction;
static int connectionID;
static BOOL runtimeAvailable;

static void ESLoadDisplaySpaceRuntime(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSOperatingSystemVersion minimum = {26, 4, 0};
        if (![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimum]) {
            return;
        }

        void *skyLight = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (!skyLight) return;

        mainConnectionFunction = dlsym(skyLight, "SLSMainConnectionID");
        currentSpaceFunction = dlsym(skyLight, "SLSManagedDisplayGetCurrentSpace");
        copySpacesForWindowsFunction = dlsym(skyLight, "SLSCopySpacesForWindows");
        spaceTypeFunction = dlsym(skyLight, "SLSSpaceGetType");
        Class operationClass = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
        SEL initializer = @selector(initWithWindows:spaceID:);
        SEL performer = @selector(performWithWMBridgeDelegate);

        if (!mainConnectionFunction || !currentSpaceFunction ||
            !copySpacesForWindowsFunction || !spaceTypeFunction ||
            !operationClass || ![operationClass instancesRespondToSelector:initializer] ||
            ![operationClass instancesRespondToSelector:performer]) {
            return;
        }

        connectionID = mainConnectionFunction();
        // A zero id means this process has no usable WindowServer connection
        // (for example inside a restricted diagnostic sandbox).
        runtimeAvailable = connectionID != 0;
    });
}

bool ESDisplaySpaceTransportAvailable(void) {
    ESLoadDisplaySpaceRuntime();
    return runtimeAvailable;
}

uint64_t ESCurrentSpaceForDisplay(uint32_t displayID) {
    ESLoadDisplaySpaceRuntime();
    if (!runtimeAvailable || displayID == 0) return 0;

    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    if (!uuid) return 0;
    CFStringRef uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid);
    CFRelease(uuid);
    if (!uuidString) return 0;
    uint64_t result = currentSpaceFunction(connectionID, uuidString);
    CFRelease(uuidString);
    return result;
}

int32_t ESSpaceType(uint64_t spaceID) {
    ESLoadDisplaySpaceRuntime();
    if (!runtimeAvailable || spaceID == 0) return -1;
    return spaceTypeFunction(connectionID, spaceID);
}

/// Returns 1 for membership, 0 for known non-membership, and -1 when the
/// membership query itself could not be completed.
int32_t ESWindowSpaceMembership(uint32_t windowID, uint64_t spaceID) {
    ESLoadDisplaySpaceRuntime();
    if (!runtimeAvailable || windowID == 0 || spaceID == 0) return -1;

    int32_t value = (int32_t)windowID;
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &value);
    if (!number) return -1;
    const void *values[] = {number};
    CFArrayRef windows = CFArrayCreate(
        kCFAllocatorDefault,
        values,
        1,
        &kCFTypeArrayCallBacks
    );
    CFRelease(number);
    if (!windows) return -1;

    CFArrayRef result = copySpacesForWindowsFunction(connectionID, 0x7, windows);
    CFRelease(windows);
    if (!result) return -1;

    int32_t membership = 0;
    CFIndex count = CFArrayGetCount(result);
    for (CFIndex index = 0; index < count; index++) {
        CFTypeRef item = CFArrayGetValueAtIndex(result, index);
        if (!item || CFGetTypeID(item) != CFNumberGetTypeID()) continue;
        uint64_t candidate = 0;
        if (CFNumberGetValue((CFNumberRef)item, kCFNumberSInt64Type, &candidate) &&
            candidate == spaceID) {
            membership = 1;
            break;
        }
    }
    CFRelease(result);
    return membership;
}

bool ESMoveWindowToSpace(uint32_t windowID, uint64_t spaceID) {
    ESLoadDisplaySpaceRuntime();
    if (!runtimeAvailable || windowID == 0 || spaceID == 0) return false;

    Class operationClass = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
    @try {
        id operation = [[operationClass alloc]
            initWithWindows:@[@(windowID)]
                    spaceID:spaceID];
        if (!operation || ![operation respondsToSelector:@selector(performWithWMBridgeDelegate)]) {
#if !__has_feature(objc_arc)
            [operation release];
#endif
            return false;
        }
        [operation performWithWMBridgeDelegate];
#if !__has_feature(objc_arc)
        [operation release];
#endif
        return true;
    } @catch (__unused NSException *exception) {
        return false;
    }
}
