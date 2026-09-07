#import "RSFloatingImageView.h"
#import "../Preferences/RSOptions.h"

@interface RSFloatingImageView () <UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate>
@property (nonatomic) CGFloat currentScale;
@end

@implementation RSFloatingImageView

- (instancetype)initWithCroppedImage:(UIImage *)image {
    self = [super initWithImage:image];
    if (self) {
        _currentScale = 1;
        self.userInteractionEnabled = YES;
        self.contentMode = UIViewContentModeScaleAspectFit;
        self.backgroundColor = UIColor.blackColor;
        self.layer.cornerRadius = 8;
        self.layer.masksToBounds = NO;
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

- (UIImage *)croppedImage { return self.image; }

- (void)tapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized)
        [self.actionDelegate floatingImageViewDidActivate:self];
}

- (void)doubleTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized && [RSOption(@"FloatDoubleClose") boolValue])
        [self.actionDelegate floatingImageViewDidRequestRemoval:self];
}

- (void)panned:(UIPanGestureRecognizer *)gesture {
    [self.actionDelegate floatingImageViewDidActivate:self];
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
    [self keepTouchableInBounds];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled)
        [self snapToNearestHorizontalEdge];
}

- (void)pinched:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan)
        [self.actionDelegate floatingImageViewDidActivate:self];
    CGFloat nextScale = MIN(MAX(self.currentScale * gesture.scale, 0.35), 2.5);
    self.currentScale = nextScale;
    self.transform = CGAffineTransformMakeScale(nextScale, nextScale);
    gesture.scale = 1;
    [self keepTouchableInBounds];
}

- (void)keepTouchableInBounds {
    if (!self.superview) return;
    CGRect frame = self.frame;
    CGFloat visible = 44;
    CGFloat width = CGRectGetWidth(self.superview.bounds);
    CGFloat height = CGRectGetHeight(self.superview.bounds);
    CGFloat dx = 0, dy = 0;
    if (CGRectGetMaxX(frame) < visible) dx = visible - CGRectGetMaxX(frame);
    if (CGRectGetMinX(frame) > width - visible) dx = width - visible - CGRectGetMinX(frame);
    if (CGRectGetMaxY(frame) < visible) dy = visible - CGRectGetMaxY(frame);
    if (CGRectGetMinY(frame) > height - visible) dy = height - visible - CGRectGetMinY(frame);
    self.center = CGPointMake(self.center.x + dx, self.center.y + dy);
}

- (void)snapToNearestHorizontalEdge {
    if (!self.superview || ![RSOption(@"FloatSnap") boolValue]) return;
    CGRect safe = UIEdgeInsetsInsetRect(self.superview.bounds, self.superview.safeAreaInsets);
    CGRect frame = self.frame;
    CGFloat left = CGRectGetMinX(safe) + CGRectGetWidth(frame) / 2.0 + 8;
    CGFloat right = CGRectGetMaxX(safe) - CGRectGetWidth(frame) / 2.0 - 8;
    if (left > right) return;
    CGFloat target = fabs(self.center.x - left) <= fabs(self.center.x - right) ? left : right;
    [UIView animateWithDuration:0.2 animations:^{
        self.center = CGPointMake(target, self.center.y);
        [self keepTouchableInBounds];
    }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    BOOL firstPair = [gesture isKindOfClass:UIPanGestureRecognizer.class] &&
                     [other isKindOfClass:UIPinchGestureRecognizer.class];
    BOOL secondPair = [gesture isKindOfClass:UIPinchGestureRecognizer.class] &&
                      [other isKindOfClass:UIPanGestureRecognizer.class];
    return firstPair || secondPair;
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        if (!weakSelf) return [UIMenu menuWithTitle:@"" children:@[]];
        UIAction *copy = [UIAction actionWithTitle:@"复制" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__kindof UIAction *action) {
            RSFloatingImageView *snap = weakSelf;
            if (snap) [snap.actionDelegate floatingImageView:snap didRequestAction:RSFloatingActionCopy];
        }];
        UIAction *save = [UIAction actionWithTitle:@"保存" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__kindof UIAction *action) {
            RSFloatingImageView *snap = weakSelf;
            if (snap) [snap.actionDelegate floatingImageView:snap didRequestAction:RSFloatingActionSave];
        }];
        UIAction *share = [UIAction actionWithTitle:@"分享" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__kindof UIAction *action) {
            RSFloatingImageView *snap = weakSelf;
            if (snap) [snap.actionDelegate floatingImageView:snap didRequestAction:RSFloatingActionShare];
        }];
        UIAction *hide = [UIAction actionWithTitle:@"隐藏当前" image:[UIImage systemImageNamed:@"eye.slash"] identifier:nil handler:^(__kindof UIAction *action) {
            RSFloatingImageView *snap = weakSelf;
            if (snap) [snap.actionDelegate floatingImageView:snap didRequestAction:RSFloatingActionHide];
        }];
        UIAction *close = [UIAction actionWithTitle:@"关闭当前" image:[UIImage systemImageNamed:@"xmark"] identifier:nil handler:^(__kindof UIAction *action) {
            RSFloatingImageView *snap = weakSelf;
            if (snap) [snap.actionDelegate floatingImageViewDidRequestRemoval:snap];
        }];
        close.attributes = UIMenuElementAttributesDestructive;
        UIAction *closeAll = [UIAction actionWithTitle:@"关闭全部" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction *action) {
            RSFloatingImageView *snap = weakSelf;
            if (snap) [snap.actionDelegate floatingImageView:snap didRequestAction:RSFloatingActionCloseAll];
        }];
        closeAll.attributes = UIMenuElementAttributesDestructive;
        UIAction *ai = [UIAction actionWithTitle:@"图片问答" image:[UIImage systemImageNamed:@"text.bubble"] identifier:nil handler:^(__kindof UIAction *action) {
            RSFloatingImageView *snap = weakSelf;
            if (snap) [snap.actionDelegate floatingImageView:snap didRequestAction:RSFloatingActionAI];
        }];
        return [UIMenu menuWithTitle:@"RegionShot" children:@[ai, copy, save, share, hide, close, closeAll]];
    }];
}

@end
