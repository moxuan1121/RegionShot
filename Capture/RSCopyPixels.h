#import <CoreGraphics/CoreGraphics.h>

// Render into owned, tightly packed pixels instead of retaining a subimage provider.
static inline CGImageRef RSCopyPixels(CGImageRef source, CGRect topLeftRect) {
    size_t width = (size_t)topLeftRect.size.width, height = (size_t)topLeftRect.size.height;
    if (!source || !width || !height || width > SIZE_MAX / 4 / height) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return NULL;
    CGContextTranslateCTM(context, -topLeftRect.origin.x,
        -(CGImageGetHeight(source) - topLeftRect.origin.y - topLeftRect.size.height));
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(source), CGImageGetHeight(source)), source);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}
