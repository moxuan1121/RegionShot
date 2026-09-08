#import "RSSelectionView.h"
#import <math.h>
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

static const CGFloat RSMinimumSelectionSize = 44.0;
static const CGFloat RSHandleHitRadius = 28.0;

@interface RSSelectionPanGestureRecognizer : UIPanGestureRecognizer
@end
@implementation RSSelectionPanGestureRecognizer
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)prevented { return YES; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventing { return NO; }
@end

@interface RSSelectionEdgePanGestureRecognizer : UIScreenEdgePanGestureRecognizer
@end
@implementation RSSelectionEdgePanGestureRecognizer
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)prevented { return YES; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventing { return NO; }
@end

@interface RSSelectionView () <UIGestureRecognizerDelegate>
@property (nonatomic) CGRect selectionRect;
@property (nonatomic) CGPoint startPoint;
@property (nonatomic) CGPoint lastPoint;
@property (nonatomic) CGPoint anchorPoint;
@property (nonatomic) RSSelectionDragMode dragMode;
@end

@implementation RSSelectionView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.multipleTouchEnabled = NO;
        UIPanGestureRecognizer *pan = [[RSSelectionPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.maximumNumberOfTouches = 1;
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        for (NSNumber *edgeValue in @[@(UIRectEdgeTop), @(UIRectEdgeLeft), @(UIRectEdgeRight), @(UIRectEdgeBottom)]) {
            UIScreenEdgePanGestureRecognizer *edge = [[RSSelectionEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
            edge.edges = edgeValue.unsignedIntegerValue; edge.maximumNumberOfTouches = 1; edge.delegate = self;
            [self addGestureRecognizer:edge]; [pan requireGestureRecognizerToFail:edge];
        }
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.delegate = self;
        [self addGestureRecognizer:doubleTap];
    }
    return self;
}

- (BOOL)hasValidSelection {
    return CGRectGetWidth(self.selectionRect) >= RSMinimumSelectionSize &&
           CGRectGetHeight(self.selectionRect) >= RSMinimumSelectionSize;
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

- (void)beginDragAtPoint:(CGPoint)point {
    self.startPoint = point;
    self.lastPoint = point;
    self.dragMode = [self modeForPoint:point];
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
        CGPoint translation = [pan translationInView:self];
        [self beginDragAtPoint:[self clampedPoint:CGPointMake(point.x - translation.x, point.y - translation.y)]];
        if (self.selectionChanged) self.selectionChanged(YES);
        return;
    }
    if (pan.state == UIGestureRecognizerStateChanged) {
        if (self.dragMode == RSSelectionDragNew) {
            self.selectionRect = [self newRectFromPoint:self.startPoint toPoint:point];
        } else if (self.dragMode == RSSelectionDragMove) {
            CGRect rect = CGRectOffset(self.selectionRect, point.x - self.lastPoint.x, point.y - self.lastPoint.y);
            rect.origin.x = MIN(MAX(rect.origin.x, 0), CGRectGetWidth(self.bounds) - rect.size.width);
            rect.origin.y = MIN(MAX(rect.origin.y, 0), CGRectGetHeight(self.bounds) - rect.size.height);
            self.selectionRect = rect;
        } else {
            self.selectionRect = [self newRectFromPoint:self.anchorPoint toPoint:point];
        }
        self.lastPoint = point;
        [self setNeedsDisplay];
        if (self.selectionChanged) self.selectionChanged(YES);
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
    if ([self hasValidSelection]) [shade appendPath:[UIBezierPath bezierPathWithRect:self.selectionRect]];
    shade.usesEvenOddFillRule = YES;
    [[UIColor colorWithWhite:0 alpha:[RSOption(@"SelectionShade") doubleValue]] setFill];
    [shade fill];
    if (![self hasValidSelection]) return;

    UIBezierPath *border = [UIBezierPath bezierPathWithRect:CGRectInset(self.selectionRect, 0.5, 0.5)];
    border.lineWidth = 1.5;
    [UIColor.whiteColor setStroke];
    [border stroke];

    CGFloat outset = RSCornerOutset(self.window.screen.scale ?: UIScreen.mainScreen.scale, 3);
    CGRect selection = CGRectInset(self.selectionRect, -outset, -outset);
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
        [UIColor.whiteColor setStroke]; handle.lineWidth = 3;
        handle.lineJoinStyle = kCGLineJoinRound;
        handle.lineCapStyle = kCGLineCapRound;
        [handle stroke];
    }
}

@end
