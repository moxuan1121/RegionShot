#import "RSSelectionView.h"
#import <math.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "../Geometry/RSGeometry.h"
#import "../Preferences/RSOptions.h"

typedef NS_ENUM(NSInteger, RSSelectionDragMode) {
    RSSelectionDragNew,
    RSSelectionDragMove,
    RSSelectionDragTopLeft,
    RSSelectionDragTopRight,
    RSSelectionDragBottomLeft,
    RSSelectionDragBottomRight,
};


static const CGFloat RSHandleHitRadius = 28.0;

@interface RSSelectionPanGestureRecognizer : UIPanGestureRecognizer
@property (nonatomic) CGPoint initialPoint;
@end
@implementation RSSelectionPanGestureRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.initialPoint = [touches.anyObject locationInView:self.view];
    [super touchesBegan:touches withEvent:event];
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)prevented { return YES; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventing { return NO; }
@end

@interface RSSelectionView () <UIGestureRecognizerDelegate>
@property (nonatomic) CGRect selectionRect;
@property (nonatomic) CGPoint startPoint;
@property (nonatomic) CGPoint lastPoint;
@property (nonatomic) CGRect dragOriginalRect;
@property (nonatomic) CGPoint anchorPoint;
@property (nonatomic) RSSelectionDragMode dragMode;
@property (nonatomic) CFTimeInterval selectionAppearedAt;
@property (nonatomic, strong) CADisplayLink *appearanceLink;
@property (nonatomic) CGFloat shadeAlpha;
@end

@implementation RSSelectionView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.multipleTouchEnabled = NO;
        self.shadeAlpha = [RSOption(@"SelectionShade") doubleValue];
        UIPanGestureRecognizer *pan = [[RSSelectionPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.maximumNumberOfTouches = 1;
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.delegate = self;
        [self addGestureRecognizer:doubleTap];
    }
    return self;
}

- (BOOL)hasValidSelection {
    return CGRectGetWidth(self.selectionRect) > 0 &&
           CGRectGetHeight(self.selectionRect) > 0;
}
- (void)selectAll { self.selectionRect = self.bounds; [self setNeedsDisplay]; if (self.selectionChanged) self.selectionChanged(NO); }

- (CGPoint)clampedPoint:(CGPoint)point {
    return CGPointMake(MIN(MAX(point.x, 0), CGRectGetWidth(self.bounds)),
                       MIN(MAX(point.y, 0), CGRectGetHeight(self.bounds)));
}

- (CGRect)newRectFromPoint:(CGPoint)start toPoint:(CGPoint)end {
    RSRectD rect = RSRectAroundAnchor(start.x, start.y, end.x, end.y, self.bounds.size.width, self.bounds.size.height);
    return CGRectMake(rect.x, rect.y, rect.width, rect.height);
}

- (RSSelectionDragMode)modeForPoint:(CGPoint)point {
    if (![self hasValidSelection]) return RSSelectionDragNew;
    CGRect rect = self.selectionRect;
    CGPoint corners[] = {
        rect.origin,
        CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)),
        CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)),
        CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)),
    };
    RSSelectionDragMode modes[] = {
        RSSelectionDragTopLeft, RSSelectionDragTopRight,
        RSSelectionDragBottomLeft, RSSelectionDragBottomRight,
    };
    for (NSUInteger index = 0; index < 4; index++) {
        if (hypot(point.x - corners[index].x, point.y - corners[index].y) <= RSHandleHitRadius)
            return modes[index];
    }
    return RSSelectionDragMove;
}

- (void)tickAppearance:(CADisplayLink *)link {
    [self setNeedsDisplay];
    if (CACurrentMediaTime() - self.selectionAppearedAt >= 0.16) { [link invalidate]; self.appearanceLink = nil; }
}
- (void)willMoveToWindow:(UIWindow *)window {
    if (!window) { [self.appearanceLink invalidate]; self.appearanceLink = nil; }
    [super willMoveToWindow:window];
}
- (void)beginDragAtPoint:(CGPoint)point {
    self.dragOriginalRect = self.selectionRect;
    self.startPoint = point;
    self.lastPoint = point;
    self.dragMode = [self modeForPoint:point];
    if (self.dragMode == RSSelectionDragNew && !UIAccessibilityIsReduceMotionEnabled()) {
        self.selectionAppearedAt = CACurrentMediaTime();
        [self.appearanceLink invalidate];
        self.appearanceLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tickAppearance:)];
        [self.appearanceLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    CGRect rect = self.selectionRect;
    switch (self.dragMode) {
        case RSSelectionDragTopLeft: self.anchorPoint = CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)); break;
        case RSSelectionDragTopRight: self.anchorPoint = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)); break;
        case RSSelectionDragBottomLeft: self.anchorPoint = CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)); break;
        case RSSelectionDragBottomRight: self.anchorPoint = rect.origin; break;
        default: self.anchorPoint = point; break;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint point = [self clampedPoint:[pan locationInView:self]];
    if (pan.state == UIGestureRecognizerStateBegan) {
        CGPoint start = [self clampedPoint:((RSSelectionPanGestureRecognizer *)pan).initialPoint];
        if (!self.hasValidSelection) {
            start.x = RSEdgeStart(start.x, self.bounds.size.width);
            start.y = RSEdgeStart(start.y, self.bounds.size.height);
        }
        [self beginDragAtPoint:start];
        if (self.selectionChanged) self.selectionChanged(YES);
    }
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged || pan.state == UIGestureRecognizerStateEnded) {
        if (self.dragMode == RSSelectionDragNew) {
            self.selectionRect = [self newRectFromPoint:self.startPoint toPoint:point];
        } else if (self.dragMode == RSSelectionDragMove) {
            CGRect rect = CGRectOffset(self.dragOriginalRect, point.x - self.startPoint.x, point.y - self.startPoint.y);
            rect.origin.x = MIN(MAX(rect.origin.x, 0), CGRectGetWidth(self.bounds) - rect.size.width);
            rect.origin.y = MIN(MAX(rect.origin.y, 0), CGRectGetHeight(self.bounds) - rect.size.height);
            self.selectionRect = rect;
        } else {
            self.selectionRect = [self newRectFromPoint:self.anchorPoint toPoint:point];
        }
        CGRect raw = self.selectionRect;
        RSRectD snapped = RSSnapSelection((RSRectD){raw.origin.x, raw.origin.y, raw.size.width, raw.size.height}, self.bounds.size.width, self.bounds.size.height, self.dragMode == RSSelectionDragMove);
        self.selectionRect = CGRectMake(snapped.x, snapped.y, snapped.width, snapped.height);
        self.lastPoint = point;
        [self setNeedsDisplay];
        if (self.selectionChanged) self.selectionChanged(pan.state != UIGestureRecognizerStateEnded);
        return;
    }
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        [self setNeedsDisplay];
        if (self.selectionChanged) self.selectionChanged(NO);
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)tap {
    CGPoint point = [tap locationInView:self];
    if (self.hasValidSelection && CGRectContainsPoint(self.selectionRect, point)) {
        if (self.doubleTapHandler) self.doubleTapHandler();
    } else if (self.cancelHandler) self.cancelHandler();
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)drawRect:(CGRect)rect {
    UIBezierPath *shade = [UIBezierPath bezierPathWithRect:self.bounds];
    CGFloat progress = self.appearanceLink ? MIN(1, MAX(0, (CACurrentMediaTime() - self.selectionAppearedAt) / 0.16)) : 1;
    progress = 1 - pow(1 - progress, 3);
    CGRect visualRect = self.selectionRect;
    if (self.appearanceLink) {
        visualRect.origin.x = self.startPoint.x + (visualRect.origin.x - self.startPoint.x) * progress;
        visualRect.origin.y = self.startPoint.y + (visualRect.origin.y - self.startPoint.y) * progress;
        visualRect.size.width *= progress; visualRect.size.height *= progress;
    }
    if ([self hasValidSelection]) [shade appendPath:[UIBezierPath bezierPathWithRect:visualRect]];
    shade.usesEvenOddFillRule = YES;
    [[UIColor colorWithWhite:0 alpha:self.shadeAlpha] setFill];
    [shade fill];
    if (![self hasValidSelection]) return;

    UIBezierPath *border = [UIBezierPath bezierPathWithRect:CGRectInset(visualRect, 0.5, 0.5)];
    border.lineWidth = 1.5;
    [[UIColor.whiteColor colorWithAlphaComponent:progress] setStroke];
    [border stroke];

    CGFloat outset = RSCornerOutset(self.window.screen.scale ?: UIScreen.mainScreen.scale, 3);
    CGRect selection = CGRectInset(visualRect, -outset, -outset);
    CGPoint corners[] = {
        selection.origin,
        CGPointMake(CGRectGetMaxX(selection), CGRectGetMinY(selection)),
        CGPointMake(CGRectGetMinX(selection), CGRectGetMaxY(selection)),
        CGPointMake(CGRectGetMaxX(selection), CGRectGetMaxY(selection)),
    };
    for (NSUInteger index = 0; index < 4; index++) {
        CGFloat dx = index == 0 || index == 2 ? 1 : -1;
        CGFloat dy = index < 2 ? 1 : -1;
        UIBezierPath *handle = [UIBezierPath bezierPath];
        [handle moveToPoint:CGPointMake(corners[index].x, corners[index].y + dy * 11)];
        [handle addLineToPoint:corners[index]];
        [handle addLineToPoint:CGPointMake(corners[index].x + dx * 11, corners[index].y)];
        [[UIColor.whiteColor colorWithAlphaComponent:progress] setStroke]; handle.lineWidth = 3;
        handle.lineJoinStyle = kCGLineJoinRound;
        handle.lineCapStyle = kCGLineCapRound;
        [handle stroke];
    }
}

@end
