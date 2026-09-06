#import "RSSelectionToolbar.h"

@interface RSSelectionToolbarButton : UIButton
@end

@implementation RSSelectionToolbarButton
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    self.imageView.frame = CGRectMake((width - 23) / 2.0, 9, 23, 23);
    self.titleLabel.frame = CGRectMake(0, 38, width, 17);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
}
@end

@implementation RSSelectionToolbar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
        self.layer.cornerRadius = 22;
        self.layer.masksToBounds = YES;
        NSArray<NSString *> *titles = @[@"截图", @"标记", @"长截图", @"扫码", @"取消"];
        NSArray<NSString *> *symbols = @[@"camera", @"pencil.tip", @"doc.on.doc", @"qrcode.viewfinder", @"xmark"];
        for (NSUInteger index = 0; index < titles.count; index++) {
            RSSelectionToolbarButton *button = [RSSelectionToolbarButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:titles[index] forState:UIControlStateNormal];
            [button setImage:[UIImage systemImageNamed:symbols[index]] forState:UIControlStateNormal];
            button.tintColor = UIColor.whiteColor;
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.tag = index;
            [button addTarget:self action:@selector(buttonPressed:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds) / self.subviews.count;
    [self.subviews enumerateObjectsUsingBlock:^(__kindof UIView *view, NSUInteger index, BOOL *stop) {
        view.frame = CGRectMake(index * width, 0, width, CGRectGetHeight(self.bounds));
    }];
}

- (void)buttonPressed:(UIButton *)button {
    if (button.tag == 0) {
        if (self.captureHandler) self.captureHandler();
    } else if (button.tag == 2) {
        if (self.longCaptureHandler) self.longCaptureHandler();
    } else if (button.tag == 4) {
        if (self.cancelHandler) self.cancelHandler();
    } else {
        NSLog(@"[RegionShot] feature not implemented");
    }
}

@end
