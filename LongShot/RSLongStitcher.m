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

static NSString *const RSLongErrorDomain = @"RegionShot.LongCapture";
enum { RSLongSignatureWidth = 96 };

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
@property (nonatomic) size_t pixelWidth;
@property (nonatomic) size_t pixelHeight;
@property (nonatomic) size_t totalHeight;
@property (nonatomic) NSUInteger capturedFrames;
@property (nonatomic) size_t captureLine;
@property (nonatomic, strong) NSData *pendingBandData;
@property (nonatomic, strong) NSMutableIndexSet *fixedRows;
@end

@implementation RSLongStitcher

- (instancetype)initWithTopInset:(CGFloat)topInset {
    if ((self = [super init])) {
        _topInset = MAX(0, topInset);
        _slices = [NSMutableArray array];
        _fixedRows = [NSMutableIndexSet indexSet];
        _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"RegionShotLong-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (NSUInteger)frameCount { return self.capturedFrames; }
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

- (NSData *)graySignature:(CGImageRef)image {
    size_t signatureHeight = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:RSLongSignatureWidth * signatureHeight];
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, RSLongSignatureWidth, signatureHeight,
        8, RSLongSignatureWidth, gray, kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, RSLongSignatureWidth, signatureHeight), image);
    CGContextRelease(context);
    return data;
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

- (NSData *)encodedCrop:(CGImageRef)image y:(size_t)y height:(size_t)height {
    CGImageRef crop = height && y + height <= CGImageGetHeight(image)
        ? CGImageCreateWithImageInRect(image, CGRectMake(0, y, CGImageGetWidth(image), height)) : nil;
    if (!crop) return nil;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, nil);
    if (destination) CGImageDestinationAddImage(destination, crop, nil);
    BOOL saved = destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination);
    CGImageRelease(crop);
    return saved ? data : nil;
}

- (CGImageRef)newPendingBand CF_RETURNS_RETAINED {
    CGImageSourceRef source = self.pendingBandData ? CGImageSourceCreateWithData((__bridge CFDataRef)self.pendingBandData, nil) : nil;
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, nil) : nil;
    if (source) CFRelease(source);
    return image;
}

- (void)recordFixedRowsFrom:(NSData *)oldGray to:(NSData *)newGray offset:(size_t)offset {
    const uint8_t *old = oldGray.bytes, *new = newGray.bytes;
    NSMutableIndexSet *stableRows = [NSMutableIndexSet indexSet];
    for (size_t row = self.captureLine; row < self.pixelHeight; row++) {
        size_t signatureRow = self.pixelHeight - 1 - row;
        unsigned same = 0, aligned = 0, stable = 0;
        for (size_t x = 0; x < RSLongSignatureWidth; x++) {
            unsigned difference = abs((int)old[signatureRow * RSLongSignatureWidth + x] - (int)new[signatureRow * RSLongSignatureWidth + x]);
            same += difference; stable += difference <= 8;
            if (signatureRow >= offset)
                aligned += abs((int)old[(signatureRow-offset) * RSLongSignatureWidth+x] - (int)new[signatureRow * RSLongSignatureWidth+x]);
        }
        if (stable >= RSLongSignatureWidth * 3 / 4 && same < RSLongSignatureWidth * 8) {
            [stableRows addIndex:row];
            if (signatureRow >= offset && aligned > same + RSLongSignatureWidth * 4)
                [self.fixedRows addIndex:row];
        }
    }
    [stableRows enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        if (NSMaxRange(range) == self.pixelHeight) [self.fixedRows addIndexesInRange:range];
    }];
}

- (BOOL)writeBand:(CGImageRef)band height:(size_t)height {
    size_t end = MIN(height, CGImageGetHeight(band)), run = 0; BOOL excluding = NO, saved = YES;
    for (size_t row = 0; row <= end; row++) {
        BOOL fixed = row < end && [self.fixedRows containsIndex:self.captureLine + row];
        if (row == 0) excluding = fixed;
        if (row == end || fixed != excluding) {
            if (!excluding && row > run) saved = saved && [self writeSlice:band y:run height:row-run];
            run = row; excluding = fixed;
        }
    }
    return saved;
}

- (RSLongAppendResult)appendImage:(UIImage *)image {
    CGImageRef clean = [self newCleanImage:image];
    if (!clean) return RSLongAppendResultUncertain;
    size_t width = CGImageGetWidth(clean), height = CGImageGetHeight(clean);
    if (!self.capturedFrames) {
        self.pixelWidth = width; self.pixelHeight = height; self.captureLine = height * 35 / 100;
        self.previousGray = [self graySignature:clean];
        self.pendingBandData = [self encodedCrop:clean y:self.captureLine height:height-self.captureLine];
        BOOL saved = self.previousGray && self.pendingBandData && [self writeSlice:clean y:0 height:self.captureLine];
        if (saved) self.capturedFrames = 1;
        CGImageRelease(clean);
        return saved ? RSLongAppendResultAdded : RSLongAppendResultUncertain;
    }
    if (width != self.pixelWidth || height != self.pixelHeight || self.totalHeight >= 60000) {
        CGImageRelease(clean); return RSLongAppendResultLimit;
    }
    NSData *gray = [self graySignature:clean];
    if (!gray) { CGImageRelease(clean); return RSLongAppendResultUncertain; }
    const size_t trim = height * 12 / 100;
    RSLongMatch match = RSFindVerticalOverlap((const uint8_t *)self.previousGray.bytes + trim * RSLongSignatureWidth,
        (const uint8_t *)gray.bytes + trim * RSLongSignatureWidth, RSLongSignatureWidth, height - trim * 2);
    if (match.changedFraction < 0.002) { CGImageRelease(clean); return RSLongAppendResultUnchanged; }
    size_t offset = match.offset;
    if (!RSLongMatchIsReliable(match) || !offset || offset >= height-self.captureLine) {
        CGImageRelease(clean); return RSLongAppendResultUncertain;
    }
    [self recordFixedRowsFrom:self.previousGray to:gray offset:offset];
    CGImageRef pending = [self newPendingBand];
    BOOL saved = pending && [self writeBand:pending height:offset];
    if (pending) CGImageRelease(pending);
    NSData *nextBand = saved ? [self encodedCrop:clean y:self.captureLine height:height-self.captureLine] : nil;
    if (saved && nextBand) {
        self.previousGray = gray; self.pendingBandData = nextBand; self.capturedFrames++;
    } else saved = NO;
    CGImageRelease(clean);
    return saved ? RSLongAppendResultAdded : RSLongAppendResultUncertain;
}

- (NSURL *)finishToURL:(NSError **)error {
    if (self.pendingBandData) {
        CGImageRef pending = [self newPendingBand];
        BOOL saved = pending && [self writeBand:pending height:CGImageGetHeight(pending)];
        if (pending) CGImageRelease(pending);
        if (!saved) {
            if (error) *error = [NSError errorWithDomain:RSLongErrorDomain code:6 userInfo:@{NSLocalizedDescriptionKey:@"无法写入长截图末段。"}];
            return nil;
        }
        self.pendingBandData = nil;
    }
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
    self.previousGray = nil; self.pendingBandData = nil; [self.fixedRows removeAllIndexes];
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
    self.previousGray = nil; self.pendingBandData = nil; [self.fixedRows removeAllIndexes]; [self.slices removeAllObjects];
    [NSFileManager.defaultManager removeItemAtPath:self.directory error:nil];
}

- (void)dealloc { [self cancel]; }

@end
