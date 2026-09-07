#import "RSSelectionToolbar.h"
#import "RSMenuSettings.h"

@interface RSSelectionToolbarButton : UIButton
@end

@implementation RSSelectionToolbarButton
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat size = RSSelectionMenuSize(YES);
    BOOL hideNames = RSSelectionMenuHideNames();
    self.imageView.frame = CGRectMake((width - size) / 2.0, 8, size, size);
    self.titleLabel.frame = hideNames ? CGRectZero : CGRectMake(0, size + 12, width, 20);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont systemFontOfSize:RSSelectionMenuSize(NO) weight:UIFontWeightMedium];
}
@end

@implementation RSSelectionToolbar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
        self.layer.cornerRadius = 22;
        self.layer.masksToBounds = YES;
        [self reloadButtons];
    }
    return self;
}

- (void)reloadButtons {
        for (UIView *view in self.subviews.copy) [view removeFromSuperview];
        for (NSDictionary *item in RSSelectionMenuItems()) {
            if (![item[@"enabled"] boolValue]) continue;
            RSSelectionToolbarButton *button = [RSSelectionToolbarButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:item[@"title"] forState:UIControlStateNormal];
            button.accessibilityLabel = item[@"title"];
            [button setImage:RSSelectionMenuIcon(item) forState:UIControlStateNormal];
            button.tintColor = UIColor.whiteColor;
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.tag = [item[@"id"] integerValue];
            [button addTarget:self action:@selector(buttonPressed:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
        }
        [self setNeedsLayout];
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
    } else if (button.tag == 1) {
        if (self.editHandler) self.editHandler();
    } else if (button.tag == 2) {
        if (self.longCaptureHandler) self.longCaptureHandler();
    } else if (button.tag == 3) {
        if (self.recognitionHandler) self.recognitionHandler();
    } else if (button.tag == 4) {
        if (self.cancelHandler) self.cancelHandler();
    } else if (button.tag == 5) {
        if (self.aiHandler) self.aiHandler();
    } else if (button.tag == 6) {
        if (self.ocrHandler) self.ocrHandler();
    } else if (button.tag == 7) {
        if (self.fullscreenHandler) self.fullscreenHandler();
    }
}

@end
