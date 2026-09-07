#import "RSScreenCapture.h"
#import "../Geometry/RSGeometry.h"
#import "RSCaptureSymbol.h"

typedef UIImage *(*RSScreenImageFunction)(void);

@implementation RSScreenCapture

+ (BOOL)isCaptureAvailable { return RSResolveCaptureSymbol() != NULL; }

+ (UIImage *)captureScreen {
    NSAssert([NSThread isMainThread], @"Screen capture must run on the main thread");
    static RSScreenImageFunction captureFunction;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        captureFunction = (RSScreenImageFunction)RSResolveCaptureSymbol();
    });
    if (!captureFunction) {
        NSLog(@"[RegionShot] _UICreateScreenUIImage unavailable");
        return nil;
    }
    UIImage *image = captureFunction();
    if (!image.CGImage) {
        NSLog(@"[RegionShot] screen capture returned no CGImage");
        return nil;
    }
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
    CGImageRef cropped = CGImageCreateWithImageInRect(source.CGImage, cropRect);
    if (!cropped) return nil;
    CGFloat scale = pixelWidth / displaySize.width;
    UIImage *result = [UIImage imageWithCGImage:cropped scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return result;
}

@end
