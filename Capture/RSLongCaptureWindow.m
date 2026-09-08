#import "RSLongCaptureWindow.h"
#import "RSScreenCapture.h"
#import "../Geometry/RSOrientation.h"
#import <notify.h>
#import "../Geometry/RSStitch.h"
#import "../Preferences/RSOptions.h"

@interface RSLongController : UIViewController @end
@implementation RSLongController
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return RSActiveOrientation(self.view.window.windowScene); }
@end
@implementation RSLongCaptureWindow {
    CGRect _captureRect;
    CGSize _displaySize;
    UIImage *(^_capture)(void);
    void (^_completion)(UIImage *);
    UIView *_panel;
    UILabel *_status;
    UIButton *_sampleButton;
    UIImageView *_preview;
    NSMutableArray<NSURL *> *_slices;
    NSURL *_directory;
    NSData *_previousStrip;
    NSUInteger _width, _height, _totalHeight;
    CGFloat _scale;
    BOOL _busy, _closed, _sampling;
    NSTimer *_timer;
    int _indicatorToken;
    dispatch_queue_t _queue;
}
- (instancetype)initWithScene:(UIWindowScene *)scene rect:(CGRect)rect displaySize:(CGSize)size
                       capture:(UIImage *(^)(void))capture completion:(void (^)(UIImage *))completion {
    self = scene ? [super initWithWindowScene:scene] : [super initWithFrame:UIScreen.mainScreen.bounds];
    if (!self) return nil;
    self.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    self.windowLevel = UIWindowLevelAlert + 220;
    self.backgroundColor = UIColor.clearColor;
    _indicatorToken = -1;
    CGFloat statusHeight = scene.statusBarManager.statusBarHidden ? 0 : CGRectGetHeight(scene.statusBarManager.statusBarFrame);
    CGRect contentRect = CGRectMake(0, MIN(statusHeight, size.height), size.width, MAX(0, size.height - statusHeight));
    _captureRect = CGRectIntersection(rect, contentRect); _displaySize = size; _capture = [capture copy]; _completion = [completion copy];
    _slices = [NSMutableArray array];
    _queue = dispatch_queue_create("com.moxuan.regionshot.stitch", DISPATCH_QUEUE_SERIAL);
    _directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[@"RegionShot-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    self.rootViewController = [RSLongController new];
    RSApplyWindowOrientation(self, RSActiveOrientation(scene));
    self.rootViewController.view.backgroundColor = UIColor.clearColor;
    _panel = [UIView new]; _panel.backgroundColor = UIColor.secondarySystemBackgroundColor; _panel.layer.cornerRadius = 18;
    [self.rootViewController.view addSubview:_panel];
    _status = [UILabel new]; _status.font = [UIFont systemFontOfSize:12]; _status.numberOfLines = 3;
    _status.text = @"缓慢向上滚动，自动对齐拼接；结束后点完成。";
    [_panel addSubview:_status];
    _preview = [UIImageView new]; _preview.contentMode = UIViewContentModeScaleAspectFit; [_panel addSubview:_preview];
    NSArray *titles = @[@"截取", @"采样", @"完成", @"取消"];
    SEL actions[] = {@selector(captureFrame), @selector(toggleSampling), @selector(finish), @selector(cancel)};
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal]; button.tag = 500 + i;
        [button addTarget:self action:actions[i] forControlEvents:UIControlEventTouchUpInside];
        [_panel addSubview:button]; if (i == 1) _sampleButton = button;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _panel.frame = CGRectMake(MAX(8, self.rootViewController.view.bounds.size.width - 250), self.rootViewController.view.safeAreaInsets.top + 8, 242, 144);
    _preview.frame = CGRectMake(8, 8, 62, 84);
    _status.frame = CGRectMake(78, 8, 156, 84);
    for (NSUInteger i = 0; i < 4; i++) [_panel viewWithTag:500 + i].frame = CGRectMake(i * 60, 96, 60, 44);
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint contentPoint = [self.rootViewController.view convertPoint:point fromView:self];
    return CGRectContainsPoint(_panel.frame, contentPoint) ? [super hitTest:point withEvent:event] : nil;
}
- (void)start {
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        _status.text = error.localizedDescription; self.hidden = NO; return;
    }
    if (CGRectIsEmpty(_captureRect) || CGRectIsNull(_captureRect)) { _status.text = @"选区只有状态栏，请取消后重新框选正文。"; self.hidden = NO; return; }
    self.hidden = NO;
    if (notify_register_check("com.moxuan.regionshot/LongCaptureState", &_indicatorToken) == NOTIFY_STATUS_OK) {
        notify_set_state(_indicatorToken, (uint64_t)NSDate.date.timeIntervalSince1970 + 4); notify_post("com.moxuan.regionshot/LongCaptureState");
    }
    [self toggleSampling]; [self captureFrame];
}
- (void)toggleSampling {
    _sampling = !_sampling;
    [_sampleButton setTitle:_sampling ? @"暂停" : @"采样" forState:UIControlStateNormal];
    [_timer invalidate]; _timer = nil;
    if (_sampling) {
        __weak typeof(self) weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:[RSOption(@"LongInterval") doubleValue] repeats:YES block:^(NSTimer *timer) { [weakSelf captureFrame]; }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}
- (void)captureFrame {
    if (_closed) return;
    if (_indicatorToken >= 0) { notify_set_state(_indicatorToken, (uint64_t)NSDate.date.timeIntervalSince1970 + 4); notify_post("com.moxuan.regionshot/LongCaptureState"); }
    if (_busy) return;
    if (!CGSizeEqualToSize(self.rootViewController.view.bounds.size, _displaySize)) {
        _status.text = @"屏幕方向已变化，请恢复原方向后继续。"; return;
    }
    _busy = YES;
    _panel.hidden = YES;
    // Give the compositor a display interval before capturing without the controls.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (self->_closed) return;
        UIImage *full = self->_capture ? self->_capture() : nil;
        self->_panel.hidden = NO;
        if (!full) { self->_busy = NO; self->_status.text = @"截图失败，可以重试。"; return; }
        dispatch_async(self->_queue, ^{
            @autoreleasepool {
                UIImage *image = [RSScreenCapture cropImage:full toRect:self->_captureRect displaySize:self->_displaySize];
                [self processImage:image];
            }
        });
    });
}
- (void)processed:(NSString *)message preview:(UIImage *)preview {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_closed) return;
        self->_busy = NO; self->_status.text = message;
        if (preview) self->_preview.image = preview;
    });
}
- (void)processImage:(UIImage *)image {
    if (image.size.width * image.scale > 1080) {
        CGSize size = CGSizeMake(1080, floor(image.size.height / image.size.width * 1080));
        UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.defaultFormat; format.scale = 1; format.opaque = YES;
        image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [image drawInRect:(CGRect){CGPointZero, size}]; }];
    }
    CGImageRef cg = image.CGImage;
    if (!cg) { [self processed:@"无法裁剪截图，请重试。" preview:nil]; return; }
    NSUInteger width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (_slices.count && (width != _width || height != _height)) {
        [self processed:@"截图尺寸改变，请结束后重新开始。" preview:nil]; return;
    }
    const int stripWidth = 96;
    int stripHeight = (int)MIN(height, 4096);
    NSMutableData *strip = [NSMutableData dataWithLength:stripWidth * stripHeight];
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(strip.mutableBytes, stripWidth, stripHeight, 8, stripWidth, gray, kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) { [self processed:@"内存不足，无法分析截图。" preview:nil]; return; }
    CGContextTranslateCTM(context, 0, stripHeight); CGContextScaleCTM(context, 1, -1);
    CGContextDrawImage(context, CGRectMake(0, 0, stripWidth, stripHeight), cg); CGContextRelease(context);
    int offset = _previousStrip ? RSStitchOffset(_previousStrip.bytes, strip.bytes, stripWidth, stripHeight, 6) : stripHeight;
    if (offset == 0) { [self processed:@"页面没有移动；继续向上滑动后截取。" preview:nil]; return; }
    if (offset < 0) { [self processed:@"无法可靠对齐；请回滚少许、保留重叠内容后再截取。" preview:nil]; return; }
    NSUInteger added = _previousStrip ? (NSUInteger)llround((double)offset * height / stripHeight) : height;
    // ponytail: final UIKit image is bounded to 12 million pixels; tiled file export is the upgrade path.
    if (width * (_totalHeight + added) > [RSOption(@"LongMaxMP") doubleValue] * 1000000 || _slices.count >= [RSOption(@"LongMaxSlices") unsignedIntegerValue]) {
        [self processed:@"已达到本次长图上限，请点完成保存。" preview:nil]; return;
    }
    CGImageRef crop = CGImageCreateWithImageInRect(cg, CGRectMake(0, height - added, width, added));
    UIImage *slice = crop ? [UIImage imageWithCGImage:crop scale:1 orientation:UIImageOrientationUp] : nil;
    if (crop) CGImageRelease(crop);
    NSData *png = slice ? UIImagePNGRepresentation(slice) : nil;
    NSURL *path = [_directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%03lu.png", (unsigned long)_slices.count]];
    NSError *error = nil;
    if (!png || ![png writeToURL:path options:NSDataWritingAtomic error:&error]) {
        [self processed:error.localizedDescription ?: @"保存分段失败，可以重试。" preview:nil]; return;
    }
    _width = width; _height = height; _scale = image.scale; _totalHeight += added;
    _previousStrip = strip; [_slices addObject:path];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(62, 84)];
    UIImage *preview = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [image drawInRect:CGRectMake(0, 0, 62, 84)]; }];
    [self processed:[NSString stringWithFormat:@"已拼接 %lu 段\n%lu × %lu 像素", (unsigned long)_slices.count,
        (unsigned long)_width, (unsigned long)_totalHeight] preview:preview];
}
- (void)finish {
    if (_busy || _closed) return;
    if (!_slices.count) { _status.text = @"请先截取至少一段。"; return; }
    _busy = YES; [_timer invalidate]; _timer = nil; _sampling = NO;
    _status.text = @"正在合成长图…";
    dispatch_async(_queue, ^{
        @autoreleasepool {
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
            format.scale = 1; format.opaque = YES;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(self->_width, self->_totalHeight) format:format];
            __block BOOL failed = NO;
            UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                CGFloat y = 0;
                for (NSURL *path in self->_slices) {
                    @autoreleasepool {
                        UIImage *slice = [UIImage imageWithContentsOfFile:path.path];
                        if (!slice.CGImage) { failed = YES; break; }
                        [slice drawAtPoint:CGPointMake(0, y)]; y += slice.size.height;
                    }
                }
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_closed) return;
                self->_busy = NO;
                if (failed || !result.CGImage) { self->_status.text = @"合成失败，分段仍保留，可重试。"; return; }
                UIImage *image = [UIImage imageWithCGImage:result.CGImage scale:self->_scale orientation:UIImageOrientationUp];
                void (^completion)(UIImage *) = self->_completion;
                self->_completion = nil; [self cancel];
                if (completion) completion(image);
            });
        }
    });
}
- (void)cancel {
    if (_closed) return;
    if (_indicatorToken >= 0) { notify_set_state(_indicatorToken, 0); notify_post("com.moxuan.regionshot/LongCaptureState"); notify_cancel(_indicatorToken); _indicatorToken = -1; }
    _previousStrip = nil;
    _closed = YES; [_timer invalidate]; _timer = nil; self.hidden = YES;
    _capture = nil;
    NSURL *directory = _directory;
    dispatch_async(_queue, ^{ [NSFileManager.defaultManager removeItemAtURL:directory error:nil]; });
    void (^completion)(UIImage *) = _completion; _completion = nil;
    if (completion) completion(nil);
}
@end
