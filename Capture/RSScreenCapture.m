#import "RSScreenCapture.h"
#import "../Geometry/RSGeometry.h"
#import "../Geometry/RSOrientation.h"
#import "RSCaptureSymbol.h"
#include <stdint.h>
#import "RSCopyPixels.h"
#import <QuartzCore/QuartzCore.h>

typedef UIImage *(*RSScreenImageFunction)(void);

@implementation RSScreenCapture

+ (UIImage *)preparedScreenImage:(UIImage *)image {
    image = [self normalizedImage:image];
    double angle = RSCaptureRotation(image.size.width, image.size.height, (int)RSActiveOrientation(nil));
    if (angle == 0) return image;
    CGSize size = CGSizeMake(image.size.height, image.size.width);
    UIGraphicsBeginImageContextWithOptions(size, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context) {
        CGContextTranslateCTM(context, size.width / 2, size.height / 2);
        CGContextRotateCTM(context, angle);
        [image drawInRect:CGRectMake(-image.size.width / 2, -image.size.height / 2,
                                     image.size.width, image.size.height)];
    }
    UIImage *rotated = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rotated ?: image;
}

+ (UIImage *)captureScreen {
    NSAssert([NSThread isMainThread], @"Screen capture must run on the main thread");
    static RSScreenImageFunction captureFunction;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        captureFunction = (RSScreenImageFunction)RSResolveCaptureSymbol();
    });
    if (!captureFunction) {

        return nil;
    }
    UIImage *image = captureFunction();
    if (!image.CGImage) {

        return nil;
    }
    return [self preparedScreenImage:image];
}

+ (UIImage *)captureScreenExcludingWindows:(NSArray<UIWindow *> *)windows {
    NSAssert(NSThread.isMainThread, @"Screen capture must run on the main thread");
    SEL selector = NSSelectorFromString(@"_snapshotExcludingWindows:withRect:");
    UIScreen *screen = UIScreen.mainScreen;
    if ([screen respondsToSelector:selector]) @try {
        NSMethodSignature *signature = [screen methodSignatureForSelector:selector];
        if (signature.numberOfArguments >= 4 && signature.methodReturnType[0] == '@') {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            NSArray *excluded = windows ?: @[];
            CGRect rect = CGRectNull;
            invocation.selector = selector;
            invocation.target = screen;
            [invocation setArgument:&excluded atIndex:2];
            [invocation setArgument:&rect atIndex:3];
            [invocation invoke];
            __unsafe_unretained id value = nil;
            [invocation getReturnValue:&value];
            if ([value isKindOfClass:UIImage.class] && ((UIImage *)value).CGImage) {
                return [self preparedScreenImage:value];
            }
        }
    } @catch (__unused NSException *exception) {}
    NSMutableArray *visible = [NSMutableArray array];
    for (UIWindow *window in windows) if (!window.hidden) { [visible addObject:window]; window.hidden = YES; }
    [CATransaction flush];
    UIImage *image = [self captureScreen];
    for (UIWindow *window in visible) window.hidden = NO;
    [CATransaction flush];
    return image;
}

+ (UIImage *)normalizedImage:(UIImage *)image {
    if (image.imageOrientation == UIImageOrientationUp) return image;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:(CGRect){CGPointZero, image.size}];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalized;
}

+ (UIImage *)cropImage:(UIImage *)image toRect:(CGRect)rect displaySize:(CGSize)displaySize {
    if (!image.CGImage || displaySize.width <= 0 || displaySize.height <= 0) return nil;
    UIImage *source = [self normalizedImage:image];
    if (!source.CGImage) return nil;
    size_t pixelWidth = CGImageGetWidth(source.CGImage);
    size_t pixelHeight = CGImageGetHeight(source.CGImage);
    RSRectD pixels = RSRectToPixels((RSRectD){rect.origin.x, rect.origin.y,
                                               rect.size.width, rect.size.height},
                                    displaySize.width, displaySize.height,
                                    pixelWidth, pixelHeight);
    if (pixels.width < 1 || pixels.height < 1) return nil;
    CGRect cropRect = CGRectMake(pixels.x, pixels.y, pixels.width, pixels.height);
    CGImageRef cropped = RSCopyPixels(source.CGImage, cropRect);
    if (!cropped) return nil;
    CGFloat scale = pixelWidth / displaySize.width;
    UIImage *result = [UIImage imageWithCGImage:cropped scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return result;
}

@end
