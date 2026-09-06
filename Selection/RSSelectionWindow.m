#import "RSSelectionWindow.h"
#import "RSSelectionToolbar.h"
#import "RSSelectionView.h"

@interface RSSelectionWindow ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) RSSelectionView *selectionView;
@property (nonatomic, strong) RSSelectionToolbar *toolbar;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@end

@implementation RSSelectionWindow

+ (UIWindow *)currentKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (window.isKeyWindow) return window;
    }
    return nil;
}

- (instancetype)initWithImage:(UIImage *)image
                       confirm:(void (^)(CGRect, CGSize))confirm
                        cancel:(dispatch_block_t)cancel {
    UIWindowScene *scene = [RSSelectionWindow currentKeyWindow].windowScene;
    self = scene ? [super initWithWindowScene:scene] : [super initWithFrame:UIScreen.mainScreen.bounds];
    if (self) {
        self.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = UIColor.blackColor;
        UIViewController *controller = [UIViewController new];
        controller.view.backgroundColor = UIColor.blackColor;
        self.rootViewController = controller;

        _imageView = [[UIImageView alloc] initWithImage:image];
        _imageView.contentMode = UIViewContentModeScaleToFill;
        [controller.view addSubview:_imageView];
        _selectionView = [[RSSelectionView alloc] initWithFrame:controller.view.bounds];
        [controller.view addSubview:_selectionView];
        _toolbar = [[RSSelectionToolbar alloc] initWithFrame:CGRectZero];
        [controller.view addSubview:_toolbar];

        __weak typeof(self) weakSelf = self;
        _toolbar.captureHandler = ^{
            RSSelectionWindow *strongSelf = weakSelf;
            if (!strongSelf.selectionView.hasValidSelection) return;
            confirm(strongSelf.selectionRect, strongSelf.displaySize);
        };
        _toolbar.cancelHandler = cancel;
    }
    return self;
}

- (CGRect)selectionRect { return self.selectionView.selectionRect; }
- (CGSize)displaySize { return self.selectionView.bounds.size; }

- (void)layoutSubviews {
    [super layoutSubviews];
    self.rootViewController.view.frame = self.bounds;
    self.imageView.frame = self.bounds;
    self.selectionView.frame = self.bounds;
    CGFloat safeBottom = self.safeAreaInsets.bottom;
    CGFloat width = MIN(CGRectGetWidth(self.bounds) - 32, 396);
    self.toolbar.frame = CGRectMake((CGRectGetWidth(self.bounds) - width) / 2.0,
                                    CGRectGetHeight(self.bounds) - safeBottom - 84,
                                    width, 72);
    [self bringSubviewToFront:self.rootViewController.view];
    [self.rootViewController.view bringSubviewToFront:self.toolbar];
}

- (void)show {
    self.previousKeyWindow = [RSSelectionWindow currentKeyWindow];
    self.hidden = NO;
    [self makeKeyAndVisible];
}

- (void)dismiss {
    self.hidden = YES;
    [self resignKeyWindow];
    [self.previousKeyWindow makeKeyWindow];
    self.toolbar.captureHandler = nil;
    self.toolbar.cancelHandler = nil;
    self.rootViewController = nil;
}

@end
