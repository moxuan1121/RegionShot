#include <stdint.h>
#include <notify.h>

#define RS_CAPTURE_CHECK "com.moxuan.regionshot/CheckCapture"
#define RS_CAPTURE_STATUS "com.moxuan.regionshot/CaptureStatus"
enum {
    RSStatusLoaded = 1u << 0,
    RSStatusEnabled = 1u << 1,
    RSStatusSymbol = 1u << 2,
    RSStatusStarted = 1u << 3,
    RSStatusHardware = 1u << 8,
    RSStatusApplication = 1u << 9,
    RSStatusEdit = 1u << 10,
    RSStatusCapturer = 1u << 11
};
