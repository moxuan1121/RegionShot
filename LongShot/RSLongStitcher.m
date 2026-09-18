#import "RSLongStitcher.h"
#import "RSLongMatch.h"
#import "RSLongPixels.h"
#import <ImageIO/ImageIO.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static NSString *const RSLongErrorDomain = @"RegionShot.LongCapture";
enum { RSLongSignatureWidth = 48, RSLongDetailWidth = 192 };

@interface RSLongSlice : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) size_t width;
@property (nonatomic) size_t height;
@end
@implementation RSLongSlice @end

@interface RSLongStitcher ()
@property (nonatomic) CGFloat topInset;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) NSMutableArray<RSLongSlice *> *slices;
@property (nonatomic, strong) NSData *previousGray;
@property (nonatomic, strong) NSData *previousDetail;
@property (nonatomic) size_t pixelWidth;
@property (nonatomic) size_t pixelHeight;
@property (nonatomic) size_t totalHeight;
@property (nonatomic) size_t previousOffset;
@end

@implementation RSLongStitcher

- (instancetype)initWithTopInset:(CGFloat)topInset {
    if ((self = [super init])) {
        _topInset = MAX(0, topInset);
        _slices = [NSMutableArray array];
        _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"RegionShotLong-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (NSUInteger)frameCount { return self.slices.count; }
- (CGFloat)estimatedHeight { return self.pixelHeight ? (CGFloat)self.totalHeight / self.pixelHeight : 0; }

- (CGImageRef)newCleanImage:(UIImage *)image CF_RETURNS_RETAINED {
    CGImageRef source = image.CGImage;
    if (!source) return nil;
    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    CGFloat scale = image.scale > 0 ? image.scale : UIScreen.mainScreen.scale;
    size_t top = MIN(height - 1, (size_t)llround(self.topInset * scale));
    size_t right = MIN(width / 20, (size_t)MAX(2, llround(3 * scale)));
    if (width <= right + 8 || height <= top + 16) return nil;
    return CGImageCreateWithImageInRect(source, CGRectMake(0, top, width - right, height - top));
}

- (NSData *)graySignature:(CGImageRef)image width:(size_t)signatureWidth {
    size_t signatureHeight = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:signatureWidth * signatureHeight];
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, signatureWidth, signatureHeight,
        8, signatureWidth, gray, kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, signatureWidth, signatureHeight), image);
    CGContextRelease(context);
    return data;
}

- (NSData *)edgeSignature:(NSData *)gray width:(size_t)width height:(size_t)height {
    NSMutableData *edges = [gray mutableCopy];
    uint8_t *pixels = edges.mutableBytes;
    for (size_t y = height - 1; y > 0; y--)
        for (size_t x = 0; x < width; x++)
            pixels[y * width + x] = (uint8_t)abs((int)pixels[y * width + x] -
                                                 (int)pixels[(y - 1) * width + x]);
    memset(pixels, 0, width);
    return edges;
}

- (void)trimRows:(size_t)rows beforeLastSlice:(BOOL)beforeLast {
    NSInteger index = (NSInteger)self.slices.count - (beforeLast ? 2 : 1);
    while (rows && index >= 0) {
        RSLongSlice *slice = self.slices[(NSUInteger)index];
        size_t removed = MIN(rows, slice.height);
        slice.height -= removed; self.totalHeight -= removed; rows -= removed;
        if (!slice.height) {
            [NSFileManager.defaultManager removeItemAtPath:slice.path error:nil];
            [self.slices removeObjectAtIndex:(NSUInteger)index];
        }
        index--;
    }
}

- (BOOL)writeSlice:(CGImageRef)image y:(size_t)y height:(size_t)height {
    if (!height || y + height > CGImageGetHeight(image)) return NO;
    CGImageRef crop = CGImageCreateWithImageInRect(image, CGRectMake(0, y, CGImageGetWidth(image), height));
    if (!crop) return NO;
    NSString *path = [self.directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%04lu.png", (unsigned long)self.slices.count]];
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, nil);
    if (destination) { CGImageDestinationAddImage(destination, crop, nil); }
    BOOL saved = destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination);
    if (saved) {
        RSLongSlice *slice = [RSLongSlice new]; slice.path = path;
        slice.width = CGImageGetWidth(crop); slice.height = CGImageGetHeight(crop);
        [self.slices addObject:slice]; self.totalHeight += slice.height;
    }
    CGImageRelease(crop);
    return saved;
}

- (RSLongAppendResult)appendImage:(UIImage *)image {
    CGImageRef clean = [self newCleanImage:image];
    if (!clean) return RSLongAppendResultUncertain;
    size_t width = CGImageGetWidth(clean), height = CGImageGetHeight(clean);
    if (!self.slices.count) {
        self.pixelWidth = width; self.pixelHeight = height;
        self.previousGray = [self graySignature:clean width:RSLongSignatureWidth];
        self.previousDetail = [self graySignature:clean width:MIN((size_t)RSLongDetailWidth, width)];
        BOOL saved = self.previousGray && self.previousDetail && [self writeSlice:clean y:0 height:height];
        CGImageRelease(clean);
        return saved ? RSLongAppendResultAdded : RSLongAppendResultUncertain;
    }
    if (width != self.pixelWidth || height != self.pixelHeight || self.totalHeight >= 60000) {
        CGImageRelease(clean); return RSLongAppendResultLimit;
    }
    size_t detailWidth = MIN((size_t)RSLongDetailWidth, width);
    NSData *gray = [self graySignature:clean width:RSLongSignatureWidth];
    NSData *detail = [self graySignature:clean width:detailWidth];
    if (!gray || !detail || !self.previousDetail) { CGImageRelease(clean); return RSLongAppendResultUncertain; }
    const size_t trim = height * 12 / 100;
    NSData *oldEdges = [self edgeSignature:self.previousGray width:RSLongSignatureWidth height:height];
    NSData *newEdges = [self edgeSignature:gray width:RSLongSignatureWidth height:height];
    RSLongMatch match = RSFindVerticalOverlap((const uint8_t *)oldEdges.bytes + trim * RSLongSignatureWidth,
        (const uint8_t *)newEdges.bytes + trim * RSLongSignatureWidth, RSLongSignatureWidth,
        height - trim * 2);
    // Mostly blank pages can move while their average difference remains tiny.
    if (match.changedFraction < 0.002) {
        CGImageRelease(clean); return RSLongAppendResultUnchanged;
    }
    NSData *oldDetailEdges = [self edgeSignature:self.previousDetail width:detailWidth height:height];
    NSData *newDetailEdges = [self edgeSignature:detail width:detailWidth height:height];
    size_t radius = MIN((size_t)24, MAX((size_t)6, height / 100));
    size_t offset = 0;
    if (RSLongMatchIsReliable(match)) {
        offset = RSRefineVerticalOffset(oldDetailEdges.bytes, newDetailEdges.bytes,
            detailWidth, height, match.offset, radius);
    } else if (self.previousOffset) {
        RSLongMatch recovered = RSFindVerticalOverlapNear(oldDetailEdges.bytes, newDetailEdges.bytes,
            detailWidth, height, self.previousOffset, MIN((size_t)48, MAX((size_t)12, self.previousOffset / 3)));
        if (RSLongMatchIsReliable(recovered)) offset = recovered.offset;
    }
    if (!offset) { CGImageRelease(clean); return RSLongAppendResultUncertain; }
    const uint8_t *oldBytes = self.previousGray.bytes, *newBytes = gray.bytes;
    size_t fixedBottom = 0, misses = 0, maximumFixed = height / 5;
    for (size_t row = 0; row < maximumFixed; row++) {
        size_t y = height - 1 - row; unsigned difference = 0;
        for (size_t x = 0; x < RSLongSignatureWidth; x += 2)
            difference += abs((int)oldBytes[y * RSLongSignatureWidth + x] - (int)newBytes[y * RSLongSignatureWidth + x]);
        double score = difference / (double)(RSLongSignatureWidth / 2);
        if (score < 3.0) { fixedBottom = row + 1; misses = 0; }
        else if (++misses >= 2) break;
    }
    size_t bottom = fixedBottom;
    size_t overlayStart = RSFindLowerFixedOverlayStart(self.previousDetail.bytes, detail.bytes,
        detailWidth, height, offset, height * 55 / 100);
    size_t overlayBottom = overlayStart < height ? height - overlayStart : 0;
    if (overlayBottom <= height * 45 / 100) bottom = MAX(bottom, overlayBottom);
    if (offset + bottom >= height || offset > height * 4 / 5) {
        CGImageRelease(clean); return RSLongAppendResultUncertain;
    }
    // Only the initial full frame includes the fixed footer. Subsequent slices exclude it.
    RSLongSlice *previous = self.slices.lastObject;
    size_t footer = self.slices.count == 1 ? MIN(bottom, previous.height - 1) : 0;
    size_t incomingEnd = height - bottom - offset;
    size_t seamWindow = MIN((size_t)48, MIN(offset, incomingEnd / 4));
    size_t rewind = RSFindQuietSeamRewind(self.previousDetail.bytes, detail.bytes,
        detailWidth, height, offset, incomingEnd, seamWindow);
    BOOL saved = [self writeSlice:clean y:incomingEnd - rewind height:offset + rewind];
    if (saved && footer + rewind) [self trimRows:footer + rewind beforeLastSlice:YES];
    if (saved) { self.previousGray = gray; self.previousDetail = detail; self.previousOffset = offset; }
    CGImageRelease(clean);
    return saved ? RSLongAppendResultAdded : RSLongAppendResultUncertain;
}

- (NSURL *)finishToURL:(NSError **)error {
    if (!self.slices.count || !self.pixelWidth || !self.totalHeight) {
        if (error) *error = [NSError errorWithDomain:RSLongErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"没有可生成的长截图。"}];
        return nil;
    }
    double scale = MIN(1.0, 30000.0 / self.totalHeight);
    double pixels = (double)self.pixelWidth * self.totalHeight;
    if (pixels * scale * scale > 12000000.0) scale = sqrt(12000000.0 / pixels);
    size_t width = MAX(1, (size_t)floor(self.pixelWidth * scale));
    size_t height = MAX(1, (size_t)floor(self.totalHeight * scale));
    size_t bytesPerRow = width * 4, length = bytesPerRow * height;
    NSString *rawPath = [self.directory stringByAppendingPathComponent:@"canvas.raw"];
    int fd = open(rawPath.fileSystemRepresentation, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0 || ftruncate(fd, (off_t)length) != 0) {
        if (fd >= 0) close(fd);
        if (error) *error = [NSError errorWithDomain:RSLongErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:@"无法创建长截图缓存。"}];
        return nil;
    }
    void *bytes = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (bytes == MAP_FAILED) {
        if (error) *error = [NSError errorWithDomain:RSLongErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey:@"长截图内存映射失败。"}];
        return nil;
    }
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    CGContextRef context = CGBitmapContextCreate(bytes, width, height, 8, bytesPerRow, color,
        bitmapInfo);
    if (!context) { CGColorSpaceRelease(color); munmap(bytes, length); return nil; }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    size_t y = 0;
    for (RSLongSlice *slice in self.slices) @autoreleasepool {
        UIImage *image = [UIImage imageWithContentsOfFile:slice.path];
        CGImageRef crop = image.CGImage ? CGImageCreateWithImageInRect(image.CGImage,
            CGRectMake(0, 0, slice.width, slice.height)) : NULL;
        if (!crop) {
            CGContextRelease(context); munmap(bytes, length);
            if (error) *error = [NSError errorWithDomain:RSLongErrorDomain code:5
                userInfo:@{NSLocalizedDescriptionKey:@"长截图片段读取失败，请重新截取。"}];
            return nil;
        }
        RSLongDrawSlice(context, crop, height, y, slice.height, scale);
        CGImageRelease(crop);
        y += slice.height;
    }
    CGContextRelease(context);
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bytes, length, NULL);
    CGImageRef output = provider ? CGImageCreate(width, height, 8, 32, bytesPerRow, color,
        bitmapInfo, provider, NULL, false, kCGRenderingIntentDefault) : NULL;
    if (provider) CGDataProviderRelease(provider);
    CGColorSpaceRelease(color);
    NSString *path = [self.directory stringByAppendingPathComponent:@"result.png"];
    CGImageDestinationRef destination = output ? CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, nil) : nil;
    if (destination) { CGImageDestinationAddImage(destination, output, nil); }
    BOOL written = destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination);
    if (output) CGImageRelease(output);
    munmap(bytes, length);
    if (!written) {
        if (error && !*error) *error = [NSError errorWithDomain:RSLongErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey:@"长截图编码失败。"}];
        return nil;
    }
    self.previousGray = nil; self.previousDetail = nil; self.previousOffset = 0;
    for (RSLongSlice *slice in self.slices) [NSFileManager.defaultManager removeItemAtPath:slice.path error:nil];
    [self.slices removeAllObjects];
    [NSFileManager.defaultManager removeItemAtPath:rawPath error:nil];
    return [NSURL fileURLWithPath:path];
}

- (UIImage *)finish:(NSError **)error {
    NSURL *url = [self finishToURL:error];
    NSData *mapped = url ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error] : nil;
    return mapped ? [UIImage imageWithData:mapped scale:UIScreen.mainScreen.scale] : nil;
}

- (void)cancel {
    self.previousGray = nil; self.previousDetail = nil; self.previousOffset = 0; [self.slices removeAllObjects];
    [NSFileManager.defaultManager removeItemAtPath:self.directory error:nil];
}

- (void)dealloc { [self cancel]; }

@end
