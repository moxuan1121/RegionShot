#import <CoreGraphics/CoreGraphics.h>

// CoreGraphics images are drawn in bottom-left coordinates; convert placement, not image orientation.
static inline void RSLongDrawSlice(CGContextRef context, CGImageRef image, size_t canvasHeight,
                                  size_t top, size_t sliceHeight, double scale) {
    double upper = canvasHeight - top * scale;
    double lower = canvasHeight - (top + sliceHeight) * scale;
    CGContextDrawImage(context, CGRectMake(0, lower, CGImageGetWidth(image) * scale, upper - lower), image);
}
