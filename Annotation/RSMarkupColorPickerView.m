#import "RSMarkupColorPickerView.h"
#import <objc/runtime.h>

@interface RSMarkupColorPickerView ()
@property (nonatomic, strong) UISlider *widthSlider;
@property (nonatomic, strong) UILabel *widthLabel;
@end

@implementation RSMarkupColorPickerView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _currentWidth = 5.0;
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
        self.layer.cornerRadius = 14.0;
        self.clipsToBounds = YES;
        [self setupColors];
        [self setupWidthSlider];
    }
    return self;
}

// Swatch palette. Colours mirror those seen in the original binary + basics.
- (void)setupColors {
    NSArray<UIColor *> *colors = @[
        [UIColor systemRedColor], [UIColor systemOrangeColor],
        [UIColor systemYellowColor], [UIColor systemGreenColor],
        [UIColor systemBlueColor], [UIColor systemPurpleColor],
        [UIColor whiteColor], [UIColor blackColor],
    ];
    CGFloat sz = 30, gap = 10, x = 14, y = 12;
    for (UIColor *c in colors) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(x, y, sz, sz);
        b.backgroundColor = c;
        b.layer.cornerRadius = sz/2;
        b.layer.borderWidth = 2;
        b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
        [b addTarget:self action:@selector(colorTapped:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(b, "c", c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addSubview:b];
        x += sz + gap;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger i = 0;
    CGFloat step = MAX(1, (self.bounds.size.width - 20)/8);
    for (UIView *view in self.subviews) if ([view isKindOfClass:UIButton.class]) {
        view.frame = CGRectMake(10 + i++ * step, 12, MIN(30,step-2), 30);
    }
    self.widthSlider.frame = CGRectMake(14,54,MAX(1,self.bounds.size.width-90),30);
    self.widthLabel.frame = CGRectMake(self.bounds.size.width-66,54,52,30);
}

- (void)colorTapped:(UIButton *)sender {
    UIColor *c = objc_getAssociatedObject(sender, "c");
    if (self.colorSelected && c) self.colorSelected(c);
}

- (void)setupWidthSlider {
    self.widthSlider = [[UISlider alloc] initWithFrame:CGRectMake(14, 54, self.bounds.size.width - 90, 30)];
    self.widthSlider.minimumValue = 1;
    self.widthSlider.maximumValue = 30;
    self.widthSlider.value = self.currentWidth;
    self.widthSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.widthSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:self.widthSlider];

    self.widthLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.bounds.size.width - 66, 54, 52, 30)];
    self.widthLabel.textColor = [UIColor whiteColor];
    self.widthLabel.textAlignment = NSTextAlignmentCenter;
    self.widthLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self addSubview:self.widthLabel];
    [self updateWidthDisplay:self.currentWidth];
}

- (void)sliderChanged:(UISlider *)s {
    self.currentWidth = s.value;
    [self updateWidthDisplay:s.value];
    if (self.widthChanged) self.widthChanged(s.value);
}

- (void)updateWidthDisplay:(CGFloat)w {
    self.widthLabel.text = [NSString stringWithFormat:@"%.0f", w];
}

@end
