#import <Foundation/Foundation.h>
#import <roothide.h>
static inline NSString *RSCameraDirectory(void) { return jbroot(@"/var/mobile/Library/Caches/com.moxuan.regionshot.camera"); }
static inline NSString *RSCameraRequestPath(void) { return [RSCameraDirectory() stringByAppendingPathComponent:@"request.plist"]; }
static inline NSString *RSCameraImagePath(void) { return [RSCameraDirectory() stringByAppendingPathComponent:@"capture.jpg"]; }
#define RS_CAMERA_FINISHED "com.moxuan.regionshot/CameraFinished"
