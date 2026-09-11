#import "../LongShot/RSLongStitcher.h"
#import <ImageIO/ImageIO.h>
#include <assert.h>
@implementation UIImage { CGImageRef _pixels; }
- (instancetype)initWithCGImage:(CGImageRef)image { if ((self = [super init])) _pixels = CGImageRetain(image); return self; }
- (CGImageRef)CGImage { return _pixels; }
- (CGFloat)scale { return 1; }
+ (instancetype)imageWithContentsOfFile:(NSString *)path { return [self imageWithData:[NSData dataWithContentsOfFile:path] scale:1]; }
+ (instancetype)imageWithData:(NSData *)data scale:(CGFloat)scale {
    if (!data) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    CGImageRef pixels = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    UIImage *image = pixels ? [[self alloc] initWithCGImage:pixels] : nil;
    if (pixels) CGImageRelease(pixels); if (source) CFRelease(source); return image;
}
- (void)dealloc { CGImageRelease(_pixels); }
@end
@implementation UIScreen
+ (UIScreen *)mainScreen { return [UIScreen new]; }
- (CGFloat)scale { return 1; }
@end
static UIImage *frame(size_t top) {
    enum { W=96, H=240 };
    uint8_t bytes[W*H*4];
    for (size_t y=0; y<H; y++) for (size_t x=0; x<W; x++) {
        uint8_t *p=bytes+(y*W+x)*4;
        p[0]=(uint8_t)((top+y)*13+x*7+(top+y)*x);
        p[1]=(uint8_t)((top+y)*19+x*3); p[2]=(uint8_t)(x*2); p[3]=255;
    }
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,bytes,sizeof(bytes),NULL);
    CGImageRef pixels=CGImageCreate(W,H,8,32,W*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,false,kCGRenderingIntentDefault);
    // Owned copy, because the input bytes are on the stack.
    CGContextRef ctx=CGBitmapContextCreate(NULL,W,H,8,W*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx,CGRectMake(0,0,W,H),pixels);
    CGImageRef owned=CGBitmapContextCreateImage(ctx);
    UIImage *result=[[UIImage alloc] initWithCGImage:owned];
    CGImageRelease(owned); CGContextRelease(ctx); CGImageRelease(pixels); CFRelease(provider); CGColorSpaceRelease(rgb);
    return result;
}
int main(void) { @autoreleasepool {
    RSLongStitcher *stitcher=[[RSLongStitcher alloc] initWithTopInset:0];
    for (size_t top=0; top<=120; top+=3) {
        assert([stitcher appendImage:frame(top)] == RSLongAppendResultAdded);
    }
    assert([stitcher appendImage:frame(120)] == RSLongAppendResultUnchanged);
    NSError *error=nil; UIImage *result=[stitcher finish:&error];
    assert(result && !error && CGImageGetHeight(result.CGImage)==360);
    size_t w=CGImageGetWidth(result.CGImage), h=CGImageGetHeight(result.CGImage);
    uint8_t *bytes=calloc(w*h,4); CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(bytes,w,h,8,w*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),result.CGImage);
    for(size_t y=0;y<h;y++) for(size_t x=0;x<w;x++) {
        const uint8_t *p=bytes+(y*w+x)*4;
        assert(abs((int)p[0]-(uint8_t)(y*13+x*7+y*x))<=1);
        assert(abs((int)p[1]-(uint8_t)(y*19+x*3))<=1);
        assert(abs((int)p[2]-(uint8_t)(x*2))<=1);
    }
    CGContextRelease(ctx); CGColorSpaceRelease(rgb); free(bytes); [stitcher cancel];
    puts("Verified 41 small-scroll frames, final height, seam pixels and image orientation");
} return 0; }
