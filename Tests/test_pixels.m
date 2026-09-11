#include <stdint.h>
#include <assert.h>
#import "../Capture/RSCopyPixels.h"
#import "../LongShot/RSLongPixels.h"
int main(void) {
    // Deliberately padded rows catch subimage stride/offset assumptions.
    uint8_t bytes[8 * 48] = {0};
    for (int y = 0; y < 8; y++) for (int x = 0; x < 9; x++) {
        uint8_t *p = bytes + y * 48 + x * 4; p[0] = x * 20; p[1] = y * 25; p[2] = 90; p[3] = 255;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bytes, sizeof(bytes), NULL);
    CGImageRef source = CGImageCreate(9, 8, 8, 32, 48, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, provider, NULL, false, kCGRenderingIntentDefault);
    CGImageRef crop = RSCopyPixels(source, CGRectMake(2, 3, 5, 4));
    CGImageRelease(source); CGDataProviderRelease(provider); CGColorSpaceRelease(space);
    assert(crop && CGImageGetWidth(crop) == 5 && CGImageGetHeight(crop) == 4);
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(crop));
    const uint8_t *out = CFDataGetBytePtr(data); size_t stride = CGImageGetBytesPerRow(crop);
    for (int y = 0; y < 4; y++) for (int x = 0; x < 5; x++) {
        const uint8_t *p = out + y * stride + x * 4;
        assert(p[0] == (x + 2) * 20 && p[1] == (y + 3) * 25 && p[2] == 90 && p[3] == 255);
    }
    CFRelease(data);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    uint8_t stitched[5 * 8 * 4] = {0};
    CGContextRef canvas = CGBitmapContextCreate(stitched, 5, 8, 8, 20, rgb,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    RSLongDrawSlice(canvas, crop, 8, 0, 4, 1);
    RSLongDrawSlice(canvas, crop, 8, 4, 4, 1);
    for (int y = 0; y < 8; y++) for (int x = 0; x < 5; x++) {
        const uint8_t *p = stitched + (y * 5 + x) * 4;
        assert(p[0] == (x + 2) * 20 && p[1] == (y % 4 + 3) * 25);
    }
    CGContextRelease(canvas); CGColorSpaceRelease(rgb); CGImageRelease(crop);
    return 0;
}
