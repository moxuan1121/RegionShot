#import "RSHIDSwipe.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <unistd.h>

typedef CFTypeRef (*RSCreateDigitizer)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    uint32_t, uint32_t, double, double, double, double, double, BOOL, BOOL, uint32_t);
typedef CFTypeRef (*RSCreateFinger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    double, double, double, double, double, BOOL, BOOL, uint32_t);
typedef CFTypeRef (*RSCreateClient)(CFAllocatorRef);
typedef CFTypeRef (*RSCreateClientWithType)(CFAllocatorRef, int, CFTypeRef);
typedef void (*RSAppendEvent)(CFTypeRef, CFTypeRef, uint32_t);
typedef void (*RSSetInteger)(CFTypeRef, uint32_t, int64_t);
typedef void (*RSSetSender)(CFTypeRef, uint64_t);
typedef void (*RSDispatchEvent)(CFTypeRef, CFTypeRef);

typedef struct {
    RSCreateDigitizer createDigitizer;
    RSCreateFinger createFinger;
    RSAppendEvent append;
    RSSetInteger setInteger;
    RSSetSender setSender;
    RSDispatchEvent dispatch;
    CFTypeRef client;
} RSHIDFunctions;

static RSHIDFunctions *RSFunctions(void) {
    static RSHIDFunctions functions; static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) handle = RTLD_DEFAULT;
        functions.createDigitizer = (RSCreateDigitizer)dlsym(handle, "IOHIDEventCreateDigitizerEvent");
        functions.createFinger = (RSCreateFinger)dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
        functions.append = (RSAppendEvent)dlsym(handle, "IOHIDEventAppendEvent");
        functions.setInteger = (RSSetInteger)dlsym(handle, "IOHIDEventSetIntegerValue");
        functions.setSender = (RSSetSender)dlsym(handle, "IOHIDEventSetSenderID");
        functions.dispatch = (RSDispatchEvent)dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
        RSCreateClient create = (RSCreateClient)dlsym(handle, "IOHIDEventSystemClientCreate");
        RSCreateClientWithType typed = (RSCreateClientWithType)dlsym(handle, "IOHIDEventSystemClientCreateWithType");
        if (create) functions.client = create(kCFAllocatorDefault);
        else if (typed) functions.client = typed(kCFAllocatorDefault, 0, nil);
    });
    return &functions;
}

static void RSSendFinger(RSHIDFunctions *f, double x, double y, BOOL touching) {
    uint64_t timestamp = mach_absolute_time();
    CFTypeRef parent = f->createDigitizer(kCFAllocatorDefault, timestamp, 3, 0, 0, 1, 0,
        0, 0, 0, 0, 0, touching, touching, 0);
    CFTypeRef finger = f->createFinger(kCFAllocatorDefault, timestamp, 1, 2, touching ? 7 : 4,
        x, y, 0, touching ? 1 : 0, 0, touching, touching, 0);
    if (!parent || !finger) { if (parent) CFRelease(parent); if (finger) CFRelease(finger); return; }
    if (f->setInteger) {
        f->setInteger(parent, 0xB0014, 1);
        f->setInteger(parent, 0xB0019, 1);
    }
    f->append(parent, finger, 0);
    if (f->setSender) f->setSender(parent, 0x8000000817319372ULL);
    f->dispatch(f->client, parent);
    CFRelease(finger); CFRelease(parent);
}

BOOL RSLongPerformUpwardSwipe(CGSize screenSize) {
    RSHIDFunctions *f = RSFunctions();
    if (!f->client || !f->createDigitizer || !f->createFinger || !f->append || !f->dispatch ||
        screenSize.width <= 0 || screenSize.height <= 0) return NO;
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.moxuan.regionshot.long-swipe", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        const NSUInteger steps = 14;
        for (NSUInteger index = 0; index <= steps; index++) {
            double progress = (double)index / steps;
            double eased = progress * progress * (3.0 - 2.0 * progress);
            RSSendFinger(f, 0.5, 0.74 - eased * 0.50, YES);
            usleep(16000);
        }
        RSSendFinger(f, 0.5, 0.24, NO);
    });
    return YES;
}
