#import "RSFloatingImageView.h"
#import "../Selection/RSMenuSettings.h"
#import "../Preferences/RSOptions.h"

static const CGFloat RSFloatingCornerRadius = 7;

@interface RSFloatingImageView () <UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate>
@property (nonatomic) CGFloat currentScale;
@property (nonatomic, strong) UIImageView *roundedImage;
@property (nonatomic) BOOL contextMenuActive;
@end

@implementation RSFloatingImageView

- (instancetype)initWithCroppedImage:(UIImage *)image {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _currentScale = 1;
        self.userInteractionEnabled = YES;
        self.contentMode = UIViewContentModeScaleAspectFit;
        self.backgroundColor = UIColor.clearColor;
        self.layer.cornerRadius = RSFloatingCornerRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = NO;
        _roundedImage = [[UIImageView alloc] initWithImage:image];
        _roundedImage.contentMode = UIViewContentModeScaleAspectFit;
        _roundedImage.layer.cornerRadius = RSFloatingCornerRadius;
        _roundedImage.layer.cornerCurve = kCACornerCurveContinuous;
        _roundedImage.clipsToBounds = YES;
        [self addSubview:_roundedImage];

        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = [RSOption(@"FloatShadow") boolValue] ? 0.35 : 0;
        self.alpha = [RSOption(@"FloatOpacity") doubleValue];
        self.layer.shadowRadius = 10;
        self.layer.shadowOffset = CGSizeMake(0, 4);

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
        UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)];
        UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
        doubleTap.numberOfTapsRequired = 2;
        [singleTap requireGestureRecognizerToFail:doubleTap];
        pan.delegate = self;
        pinch.delegate = self;
        [self addGestureRecognizer:pan];
        [self addGestureRecognizer:pinch];
        [self addGestureRecognizer:singleTap];
        [self addGestureRecognizer:doubleTap];
        [self addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews]; self.roundedImage.frame = self.bounds;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:RSFloatingCornerRadius].CGPath;
}
- (UIImage *)image { return self.roundedImage.image; }
- (void)setImage:(UIImage *)image { self.roundedImage.image = image; }
- (UIImage *)croppedImage { return self.roundedImage.image; }
- (void)setShadowVisible:(BOOL)visible { self.layer.shadowOpacity = visible && [RSOption(@"FloatShadow") boolValue] ? 0.35 : 0; }

- (void)tapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized)
        [self.actionDelegate floatingImageViewDidActivate:self];
}

- (void)doubleTapped:(UITapGestureRecognizer *)gesture {
    if (!self.contextMenuActive && gesture.state == UIGestureRecognizerStateRecognized && [RSOption(@"FloatDoubleClose") boolValue])
        [self.actionDelegate floatingImageViewDidRequestRemoval:self];
}

- (void)panned:(UIPanGestureRecognizer *)gesture {
    [self.actionDelegate floatingImageViewDidActivate:self];
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}

- (void)pinched:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan)
        [self.actionDelegate floatingImageViewDidActivate:self];
    CGFloat nextScale = MIN(MAX(self.currentScale * gesture.scale, 0.35), 2.5);
    self.currentScale = nextScale;
    self.transform = CGAffineTransformMakeScale(nextScale, nextScale);
    gesture.scale = 1;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    BOOL firstPair = [gesture isKindOfClass:UIPanGestureRecognizer.class] &&
                     [other isKindOfClass:UIPinchGestureRecognizer.class];
    BOOL secondPair = [gesture isKindOfClass:UIPinchGestureRecognizer.class] &&
                      [other isKindOfClass:UIPanGestureRecognizer.class];
    return firstPair || secondPair;
}

- (UITargetedPreview *)menuPreview {
    UIPreviewParameters *parameters = [UIPreviewParameters new];
    parameters.backgroundColor = UIColor.clearColor;
    parameters.visiblePath = [UIBezierPath bezierPathWithRoundedRect:self.roundedImage.bounds cornerRadius:RSFloatingCornerRadius];
    return [[UITargetedPreview alloc] initWithView:self.roundedImage parameters:parameters];
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration { return [self menuPreview]; }
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration { return [self menuPreview]; }
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    self.contextMenuActive = YES;
    for (UIGestureRecognizer *gesture in self.gestureRecognizers)
        if ([gesture isKindOfClass:UITapGestureRecognizer.class]) gesture.enabled = NO;
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    void (^finish)(void) = ^{
        self.contextMenuActive = NO;
        for (UIGestureRecognizer *gesture in self.gestureRecognizers)
            if ([gesture isKindOfClass:UITapGestureRecognizer.class]) gesture.enabled = YES;
    };
    if (animator) [animator addCompletion:finish]; else finish();
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        if (!weakSelf) return [UIMenu menuWithTitle:@"" children:@[]];
        NSMutableArray *actions = [NSMutableArray array];
        for (NSDictionary *item in RSFloatingMenuItems()) {
            if (![item[@"enabled"] boolValue]) continue;
            NSInteger identifier = [item[@"id"] integerValue];
            UIAction *action = [UIAction actionWithTitle:item[@"title"] image:RSSelectionMenuIcon(item) identifier:nil handler:^(__kindof UIAction *sender) {
                RSFloatingImageView *snap = weakSelf;
                if (snap) [snap.actionDelegate floatingImageView:snap didRequestAction:(RSFloatingAction)identifier];
            }];
            if (identifier == RSFloatingActionCloseAll || identifier == RSFloatingActionCloseCurrent) action.attributes = UIMenuElementAttributesDestructive;
            [actions addObject:action];
        }
        return [UIMenu menuWithTitle:@"RegionShot" children:actions];
    }];
}

@end
