#import "RSLongStitcher.h"
#import "RSLongMatch.h"
#import <ImageIO/ImageIO.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#include <math.h>
#include <stdlib.h>

static NSString *const RSLongErrorDomain = @"RegionShot.LongCapture";
enum { RSLongSignatureWidth = 48, RSLongSignatureHeight = 240 };

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

- (NSData *)graySignature:(CGImageRef)image {
    NSMutableData *data = [NSMutableData dataWithLength:RSLongSignatureWidth * RSLongSignatureHeight];
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, RSLongSignatureWidth, RSLongSignatureHeight,
        8, RSLongSignatureWidth, gray, kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, RSLongSignatureWidth, RSLongSignatureHeight), image);
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

- (RSLongAppendResult)appendImage:(UIImage *)image {
    CGImageRef clean = [self newCleanImage:image];
    if (!clean) return RSLongAppendResultUncertain;
    size_t width = CGImageGetWidth(clean), height = CGImageGetHeight(clean);
    if (!self.slices.count) {
        self.pixelWidth = width; self.pixelHeight = height;
        self.previousGray = [self graySignature:clean];
        BOOL saved = self.previousGray && [self writeSlice:clean y:0 height:height];
        CGImageRelease(clean);
        return saved ? RSLongAppendResultAdded : RSLongAppendResultUncertain;
    }
    if (width != self.pixelWidth || height != self.pixelHeight || self.totalHeight >= 60000) {
        CGImageRelease(clean); return RSLongAppendResultLimit;
    }
    NSData *gray = [self graySignature:clean];
    if (!gray) { CGImageRelease(clean); return RSLongAppendResultUncertain; }
    const size_t trim = RSLongSignatureHeight * 12 / 100;
    RSLongMatch match = RSFindVerticalOverlap((const uint8_t *)self.previousGray.bytes + trim * RSLongSignatureWidth,
        (const uint8_t *)gray.bytes + trim * RSLongSignatureWidth, RSLongSignatureWidth,
        RSLongSignatureHeight - trim * 2);
    if (match.unchangedScore < 2.2) {
        self.previousGray = gray; CGImageRelease(clean); return RSLongAppendResultUnchanged;
    }
    if (!match.offset || match.score > 18.0) {
        CGImageRelease(clean); return RSLongAppendResultUncertain;
    }
    size_t offset = (size_t)llround((double)match.offset * height /
        (double)(RSLongSignatureHeight - trim * 2));
    const uint8_t *oldBytes = self.previousGray.bytes, *newBytes = gray.bytes;
    size_t fixedBottom = 0, misses = 0, maximumFixed = RSLongSignatureHeight / 5;
    for (size_t row = 0; row < maximumFixed; row++) {
        size_t y = RSLongSignatureHeight - 1 - row; unsigned difference = 0;
        for (size_t x = 0; x < RSLongSignatureWidth; x += 2)
            difference += abs((int)oldBytes[y * RSLongSignatureWidth + x] - (int)newBytes[y * RSLongSignatureWidth + x]);
        double score = difference / (double)(RSLongSignatureWidth / 2);
        if (score < 3.0) { fixedBottom = row + 1; misses = 0; }
        else if (++misses >= 2) break;
    }
    size_t bottom = (size_t)llround((double)fixedBottom * height / RSLongSignatureHeight);
    if (offset <= bottom + 4 || offset > height * 4 / 5) {
        CGImageRelease(clean); return RSLongAppendResultUncertain;
    }
    BOOL saved = [self writeSlice:clean y:height - offset height:offset - bottom];
    if (saved) self.previousGray = gray;
    CGImageRelease(clean);
    return saved ? RSLongAppendResultAdded : RSLongAppendResultUncertain;
}

- (UIImage *)finish:(NSError **)error {
    if (!self.slices.count || !self.pixelWidth || !self.totalHeight) {
        if (error) *error = [NSError errorWithDomain:RSLongErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"没有可生成的长截图。"}];
        return nil;
    }
    double scale = MIN(1.0, 30000.0 / self.totalHeight);
    double pixels = (double)self.pixelWidth * self.totalHeight;
    if (pixels * scale * scale > 28000000.0) scale = sqrt(28000000.0 / pixels);
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
    CGContextRef context = CGBitmapContextCreate(bytes, width, height, 8, bytesPerRow, color,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(color);
    if (!context) { munmap(bytes, length); return nil; }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, scale, -scale);
    size_t y = 0;
    for (RSLongSlice *slice in self.slices) @autoreleasepool {
        UIImage *image = [UIImage imageWithContentsOfFile:slice.path];
        if (image.CGImage) CGContextDrawImage(context, CGRectMake(0, y, slice.width, slice.height), image.CGImage);
        y += slice.height;
    }
    CGImageRef output = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    NSString *path = [self.directory stringByAppendingPathComponent:@"result.png"];
    CGImageDestinationRef destination = output ? CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, nil) : nil;
    if (destination) { CGImageDestinationAddImage(destination, output, nil); }
    BOOL written = destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination);
    if (output) CGImageRelease(output);
    munmap(bytes, length);
    NSData *mapped = written ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error] : nil;
    UIImage *result = mapped ? [UIImage imageWithData:mapped scale:UIScreen.mainScreen.scale] : nil;
    if (!result && error && !*error) *error = [NSError errorWithDomain:RSLongErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey:@"长截图编码失败。"}];
    return result;
}

- (void)cancel {
    self.previousGray = nil; [self.slices removeAllObjects];
    [NSFileManager.defaultManager removeItemAtPath:self.directory error:nil];
}

- (void)dealloc { [self cancel]; }

@end
