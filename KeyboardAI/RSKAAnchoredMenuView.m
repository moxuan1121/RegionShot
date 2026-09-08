// Adapted from Kayoko, GPL-3.0; see THIRD_PARTY.md.
#import "RSKAAnchoredMenuView.h"

static NSInteger const kKAAnchoredMenuTag = 0x4B4D4E55;
static CGFloat const kKAAnchoredMenuWidth = 190.0;
static CGFloat const kKAAnchoredMenuRowHeight = 34.0;
static CGFloat const kKAAnchoredMenuMargin = 8.0;

@interface RSKAAnchoredMenuView ()
@property(nonatomic, strong) UIView *cardView;
@property(nonatomic, strong) UIStackView *stackView;
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) NSMutableArray<dispatch_block_t> *handlers;
@property(nonatomic, assign) NSInteger highlightedIndex;
@end

@implementation RSKAAnchoredMenuView

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.tag = kKAAnchoredMenuTag;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
        [self addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];

        _handlers = [NSMutableArray array];
        _highlightedIndex = NSNotFound;
        _menuWidth = kKAAnchoredMenuWidth;
        _cardView = [[UIView alloc] init];
        _cardView.layer.cornerRadius = 12.0;
        _cardView.layer.cornerCurve = kCACornerCurveContinuous;
        _cardView.layer.shadowColor = UIColor.blackColor.CGColor;
        _cardView.layer.shadowOpacity = 0.22;
        _cardView.layer.shadowRadius = 10.0;
        _cardView.layer.shadowOffset = CGSizeMake(0, 4);
        [self addSubview:_cardView];

        _stackView = [[UIStackView alloc] init];
        _stackView.axis = UILayoutConstraintAxisVertical;
        _stackView.distribution = UIStackViewDistributionFillEqually;
        _stackView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _stackView.layer.cornerRadius = 12.0;
        _stackView.layer.cornerCurve = kCACornerCurveContinuous;
        _stackView.clipsToBounds = YES;
        _scrollView = [UIScrollView new];
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.layer.cornerRadius = 12;
        _scrollView.clipsToBounds = YES;
        [_cardView addSubview:_scrollView];
        [_scrollView addSubview:_stackView];

        UILongPressGestureRecognizer *slideGesture =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleSlideGesture:)];
        slideGesture.minimumPressDuration = 0.12;
        [self addGestureRecognizer:slideGesture];
    }
    return self;
}

- (void)addItemWithTitle:(NSString *)title
                   image:(UIImage *)image
             destructive:(BOOL)destructive
                 handler:(dispatch_block_t)handler {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = self.handlers.count;
    button.contentHorizontalAlignment = self.centersTitles ? UIControlContentHorizontalAlignmentCenter
                                                           : UIControlContentHorizontalAlignmentLeft;
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(0, 12, 0, 12);
    configuration.imagePadding = 8;
    configuration.baseForegroundColor = destructive ? UIColor.systemRedColor : UIColor.labelColor;
    configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:13.0];
    configuration.attributedTitle = [[NSAttributedString alloc]
        initWithString:title
            attributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular] }];
    button.configuration = configuration;
    button.configurationUpdateHandler = ^(UIButton *updatedButton) {
      UIButtonConfiguration *updatedConfiguration = updatedButton.configuration;
      updatedConfiguration.background.backgroundColor =
          updatedButton.highlighted ? UIColor.tertiarySystemFillColor : UIColor.clearColor;
      updatedButton.configuration = updatedConfiguration;
    };
    if (image) {
        [button setImage:image forState:UIControlStateNormal];
    }
    UIView *separator = [[UIView alloc] init];
    separator.backgroundColor = UIColor.separatorColor;
    separator.userInteractionEnabled = NO;
    [button addSubview:separator];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:12.0],
        [separator.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5]
    ]];
    [button addTarget:self action:@selector(handleItem:) forControlEvents:UIControlEventTouchUpInside];
    [self.handlers addObject:[handler copy]];
    [self.stackView addArrangedSubview:button];
}

- (void)presentFromView:(UIView *)sourceView inView:(UIView *)hostView {
    [[hostView viewWithTag:kKAAnchoredMenuTag] removeFromSuperview];
    self.frame = hostView.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [hostView addSubview:self];

    CGRect sourceFrame = [sourceView convertRect:sourceView.bounds toView:hostView];
    CGFloat contentHeight = self.handlers.count * kKAAnchoredMenuRowHeight;
    CGFloat top = hostView.safeAreaInsets.top + 8;
    CGFloat bottom = hostView.bounds.size.height - hostView.safeAreaInsets.bottom - 8;
    CGFloat height = MIN(contentHeight, bottom - top);
    CGFloat width = MIN(self.menuWidth, CGRectGetWidth(hostView.bounds) - kKAAnchoredMenuMargin * 2.0);
    CGFloat x = MIN(MAX(CGRectGetMidX(sourceFrame) - width / 2.0, kKAAnchoredMenuMargin),
                    CGRectGetWidth(hostView.bounds) - width - kKAAnchoredMenuMargin);
    CGFloat y = self.presentsBelowSource ? CGRectGetMaxY(sourceFrame) + 6.0
                                         : CGRectGetMinY(sourceFrame) - height - 6.0;
    if (!self.presentsBelowSource && y < kKAAnchoredMenuMargin) {
        y = MIN(CGRectGetMaxY(sourceFrame) + 6.0,
                CGRectGetHeight(hostView.bounds) - height - kKAAnchoredMenuMargin);
    }
    y = MIN(y, CGRectGetHeight(hostView.bounds) - height - kKAAnchoredMenuMargin);
    y = MAX(top, MIN(y, bottom - height));
    self.cardView.frame = CGRectMake(x, y, width, height);
    self.scrollView.frame = self.cardView.bounds;
    self.scrollView.contentSize = CGSizeMake(width, contentHeight);
    self.stackView.frame = CGRectMake(0, 0, width, contentHeight);
    self.alpha = 0;
    self.cardView.transform = CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:0.16
                     animations:^{
                       self.alpha = 1;
                       self.cardView.transform = CGAffineTransformIdentity;
                     }];
}

- (void)handleItem:(UIButton *)sender {
    [self performItemAtIndex:sender.tag];
}

- (void)performItemAtIndex:(NSInteger)index {
    dispatch_block_t handler = index >= 0 && index < (NSInteger)self.handlers.count ? self.handlers[index] : nil;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self dismiss];
    if (handler) {
        handler();
    }
}

- (void)handleSlideGesture:(UILongPressGestureRecognizer *)gesture {
    [self trackGestureRecognizer:gesture];
}

- (void)trackGestureRecognizer:(UIGestureRecognizer *)gesture {
    CGPoint viewport = [gesture locationInView:self.scrollView];
    if (gesture.state == UIGestureRecognizerStateChanged && self.scrollView.contentSize.height > self.scrollView.bounds.size.height) {
        CGFloat y = self.scrollView.contentOffset.y;
        if (viewport.y < y + 24) y -= 12;
        else if (viewport.y > y + self.scrollView.bounds.size.height - 24) y += 12;
        self.scrollView.contentOffset = CGPointMake(0, MAX(0, MIN(y, self.scrollView.contentSize.height - self.scrollView.bounds.size.height)));
    }
    CGPoint point = [gesture locationInView:self.stackView];
    NSInteger index = CGRectContainsPoint(self.stackView.bounds, point) && CGRectContainsPoint(self.scrollView.bounds, viewport)
                          ? MIN((NSInteger)(point.y / kKAAnchoredMenuRowHeight),
                                (NSInteger)self.handlers.count - 1)
                          : NSNotFound;
    if (index != self.highlightedIndex) {
        if (index != NSNotFound) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        }
        self.highlightedIndex = index;
        [self.stackView.arrangedSubviews enumerateObjectsUsingBlock:^(UIView *view, NSUInteger itemIndex, BOOL *stop) {
          (void)stop;
          [(UIButton *)view setHighlighted:(NSInteger)itemIndex == index];
        }];
    }
    if (gesture.state == UIGestureRecognizerStateEnded) {
        NSInteger selectedIndex = self.highlightedIndex;
        self.highlightedIndex = NSNotFound;
        if (selectedIndex != NSNotFound) {
            [self performItemAtIndex:selectedIndex];
        } else {
            [self dismiss];
        }
    } else if (gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        self.highlightedIndex = NSNotFound;
        [self dismiss];
    }
}

- (void)dismiss {
    dispatch_block_t callback = self.onDismiss;
    self.onDismiss = nil;
    if (callback) callback();
    if (!self.animatesDismissal || !self.superview) {
        [self removeFromSuperview];
        return;
    }
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.14
                     animations:^{
                       self.alpha = 0;
                       self.cardView.transform = CGAffineTransformMakeScale(0.96, 0.96);
                     }
                     completion:^(__unused BOOL finished) {
                       [self removeFromSuperview];
                     }];
}

@end
