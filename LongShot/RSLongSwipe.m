#import "RSLongSwipe.h"
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <unistd.h>

typedef CFTypeRef (*RSCreateDigitizerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    uint32_t, uint32_t, double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef CFTypeRef (*RSCreateFingerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef CFTypeRef (*RSCreateClient)(CFAllocatorRef);
typedef void (*RSAppendEvent)(CFTypeRef, CFTypeRef, uint32_t);
typedef void (*RSSetInteger)(CFTypeRef, uint32_t, int64_t);
typedef void (*RSSetSenderID)(CFTypeRef, uint64_t);
typedef void (*RSDispatchEvent)(CFTypeRef, CFTypeRef);

static RSCreateDigitizerEvent RSCreateDigitizer;
static RSCreateFingerEvent RSCreateFinger;
static RSAppendEvent RSAppend;
static RSSetInteger RSSetField;
static RSSetSenderID RSSetSender;
static RSDispatchEvent RSDispatch;
static CFTypeRef RSClient;

static void *RSSymbol(const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol) return symbol;
    static void *iokit;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY); });
    return iokit ? dlsym(iokit, name) : NULL;
}

static BOOL RSPrepareSwipe(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        RSCreateDigitizer = (RSCreateDigitizerEvent)RSSymbol("IOHIDEventCreateDigitizerEvent");
        RSCreateFinger = (RSCreateFingerEvent)RSSymbol("IOHIDEventCreateDigitizerFingerEvent");
        RSAppend = (RSAppendEvent)RSSymbol("IOHIDEventAppendEvent");
        RSSetField = (RSSetInteger)RSSymbol("IOHIDEventSetIntegerValue");
        RSSetSender = (RSSetSenderID)RSSymbol("IOHIDEventSetSenderID");
        RSDispatch = (RSDispatchEvent)RSSymbol("IOHIDEventSystemClientDispatchEvent");
        RSCreateClient createClient = (RSCreateClient)RSSymbol("IOHIDEventSystemClientCreate");
        if (createClient) RSClient = createClient(kCFAllocatorDefault);
    });
    return RSClient && RSCreateDigitizer && RSCreateFinger && RSAppend && RSSetField && RSSetSender && RSDispatch;
}

static BOOL RSSendFinger(CGFloat y, uint32_t phase) {
    uint32_t mask = phase == 1 ? 4 : 3;
    BOOL touching = phase != 2;
    uint64_t timestamp = mach_absolute_time();
    CFTypeRef parent = RSCreateDigitizer(kCFAllocatorDefault, timestamp, 3, 0, 0, 1, 0,
        0.5, y, 0, 0, 0, true, false, 0);
    CFTypeRef finger = RSCreateFinger(kCFAllocatorDefault, timestamp, 1, 2, mask,
        0.5, y, 0, 0, 0, touching, touching, 0);
    if (!parent || !finger) {
        if (finger) CFRelease(finger);
        if (parent) CFRelease(parent);
        return NO;
    }
    RSAppend(parent, finger, 0);
    RSSetField(parent, 0xB0014, 1);
    RSSetField(parent, 0xB0019, 1);
    RSSetSender(parent, 0x8000000817319372ULL);
    RSDispatch(RSClient, parent);
    CFRelease(finger);
    CFRelease(parent);
    return YES;
}

void RSPerformLongStepSwipe(CGFloat startY, CGFloat endY, void (^completion)(BOOL success)) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.moxuan.regionshot.long-swipe", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        BOOL ready = RSPrepareSwipe();
        if (ready) {
            BOOL began = RSSendFinger(startY, 0);
            ready = began;
            for (NSUInteger step = 1; step <= 18; step++) {
                CGFloat progress = step / 18.0;
                ready = RSSendFinger(startY + (endY - startY) * progress, 1);
                if (!ready) break;
                usleep(12000);
            }
            for (NSUInteger hold = 0; ready && hold < 5; hold++) { ready = RSSendFinger(endY, 1); usleep(15000); }
            if (began) {
                BOOL ended = RSSendFinger(endY, 2);
                ready = ready && ended;
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 450 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            completion(ready);
        });
    });
}
