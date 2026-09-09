#import "RSMarkupAnnotationCanvas.h"

@interface RSMarkupAnnotationCanvas ()
@property (nonatomic) BOOL isDrawing;
@property (nonatomic) CGPoint currentStart;
@property (nonatomic) CGPoint currentEnd;
@property (nonatomic, strong) NSMutableArray<NSValue *> *currentPathPoints;
@property (nonatomic, strong) RSMarkupAnnotationItem *liveItem;   // item being drawn
@end

@implementation RSMarkupAnnotationCanvas

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        _items = [NSMutableArray array];
        _currentPathPoints = [NSMutableArray array];
        _strokeColor = [UIColor systemRedColor];
        _lineWidth = 5.0;
        _drawMode = RSMarkupDrawModeArrow;
    }
    return self;
}

- (void)resizeDrawingToSize:(CGSize)size {
    CGSize old = self.bounds.size;
    if (old.width <= 0 || old.height <= 0 || CGSizeEqualToSize(old, size)) return;
    CGFloat sx = size.width / old.width, sy = size.height / old.height;
    for (RSMarkupAnnotationItem *item in self.items) {
        item.startPoint = CGPointMake(item.startPoint.x*sx, item.startPoint.y*sy);
        item.endPoint = CGPointMake(item.endPoint.x*sx, item.endPoint.y*sy);
        for (NSUInteger i=0; i<item.pathPoints.count; i++) {
            CGPoint p = item.pathPoints[i].CGPointValue;
            item.pathPoints[i] = [NSValue valueWithCGPoint:CGPointMake(p.x*sx,p.y*sy)];
        }
        item.lineWidth *= sx;
        if (item.textAnnotation) {
            item.textAnnotation.center = CGPointMake(item.textAnnotation.center.x*sx,item.textAnnotation.center.y*sy);
            item.textAnnotation.fontSize *= sx;
        }
    }
    [self setNeedsDisplay];
}

#pragma mark - Touch handling

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.drawMode == RSMarkupDrawModeText) return; // text handled by the VC
    CGPoint p = [touches.anyObject locationInView:self];
    self.isDrawing = YES;
    self.currentStart = p;
    self.currentEnd = p;
    [self.currentPathPoints removeAllObjects];
    [self.currentPathPoints addObject:[NSValue valueWithCGPoint:p]];

    RSMarkupAnnotationItem *item = [RSMarkupAnnotationItem new];
    item.type = self.drawMode;
    item.color = self.strokeColor;
    item.lineWidth = self.lineWidth;
    item.startPoint = p;
    item.endPoint = p;
    self.liveItem = item;
    item.pathPoints = [self.currentPathPoints mutableCopy];
    [self.items addObject:item];
    [self setNeedsDisplay];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.isDrawing) return;
    CGPoint p = [touches.anyObject locationInView:self];
    self.currentEnd = p;
    self.liveItem.endPoint = p;
    if (self.drawMode == RSMarkupDrawModeScribble || self.drawMode == RSMarkupDrawModeMosaic) {
        [self.currentPathPoints addObject:[NSValue valueWithCGPoint:p]];
        self.liveItem.pathPoints = [self.currentPathPoints mutableCopy];
    }
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesMoved:touches withEvent:event];
    self.isDrawing = NO;
    self.liveItem = nil;
    [self setNeedsDisplay];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.liveItem) [self.items removeObjectIdenticalTo:self.liveItem];
    [self setNeedsDisplay];
    self.isDrawing = NO;
    self.liveItem = nil;
}

#pragma mark - Edit ops

- (void)undo {
    [self.items removeLastObject];
    [self setNeedsDisplay];
}

- (void)clearAll {
    [self.items removeAllObjects];
    [self setNeedsDisplay];
}

#pragma mark - Drawing

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    // 1) 普通标记先画（箭头/方框/圆/涂鸦/打码/放大镜）
    for (RSMarkupAnnotationItem *item in self.items) {
        if (item.type == RSMarkupDrawModeHighlight) continue;
        [self drawItem:item inContext:ctx];
    }
    // 2) 高亮遮罩整帧画一次：全屏压暗 + 挖空所有高亮区，再给每个高亮区描边
    //    （1.6 新增：drawHighlightMaskInContext: / drawHighlightBorderItem:inContext:）
    BOOL hasHighlight = NO;
    for (RSMarkupAnnotationItem *item in self.items)
        if (item.type == RSMarkupDrawModeHighlight) { hasHighlight = YES; break; }
    if (hasHighlight) {
        [self drawHighlightMaskInContext:ctx];
        for (RSMarkupAnnotationItem *item in self.items)
            if (item.type == RSMarkupDrawModeHighlight)
                [self drawHighlightBorderItem:item inContext:ctx];
    }
}

- (void)drawItem:(RSMarkupAnnotationItem *)item inContext:(CGContextRef)ctx {
    CGContextSetStrokeColorWithColor(ctx, item.color.CGColor);
    CGContextSetFillColorWithColor(ctx, item.color.CGColor);
    CGContextSetLineWidth(ctx, item.lineWidth);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);

    switch (item.type) {
        case RSMarkupDrawModeArrow:
            [self drawArrowFrom:item.startPoint to:item.endPoint color:item.color
                      lineWidth:item.lineWidth inContext:ctx];
            break;
        case RSMarkupDrawModeRect: {
            CGRect r = [self rectFrom:item.startPoint to:item.endPoint];
            CGContextStrokeRect(ctx, r);
            break;
        }
        case RSMarkupDrawModeCircle: {
            CGRect r = [self rectFrom:item.startPoint to:item.endPoint];
            CGContextStrokeEllipseInRect(ctx, r);
            break;
        }
        case RSMarkupDrawModeScribble: {
            [self strokePath:item.pathPoints inContext:ctx];
            break;
        }
        case RSMarkupDrawModeMosaic: {
            [self drawMosaicWithPoints:item.pathPoints cell:MAX(4, item.lineWidth * 2) inContext:ctx];
            break;
        }
        case RSMarkupDrawModeMagnifier: {
            [self drawMagnifierItem:item inContext:ctx];
            break;
        }
        case RSMarkupDrawModeText: {
            RSMarkupTextAnnotation *a = item.textAnnotation;
            if (!a.text.length) break;
            NSDictionary *attrs = @{NSFontAttributeName:[UIFont systemFontOfSize:a.fontSize], NSForegroundColorAttributeName:[a.textColor colorWithAlphaComponent:a.opacity]};
            CGSize size = [a.text sizeWithAttributes:attrs];
            [a.text drawAtPoint:CGPointMake(a.center.x-size.width/2, a.center.y-size.height/2) withAttributes:attrs];
            break;
        }
        default: break;
    }
}

- (CGRect)rectFrom:(CGPoint)a to:(CGPoint)b {
    return CGRectMake(MIN(a.x,b.x), MIN(a.y,b.y), fabs(a.x-b.x), fabs(a.y-b.y));
}

- (void)strokePath:(NSArray<NSValue *> *)pts inContext:(CGContextRef)ctx {
    if (pts.count == 1) { CGPoint p = pts.firstObject.CGPointValue; CGContextMoveToPoint(ctx,p.x,p.y); CGContextAddLineToPoint(ctx,p.x + 0.01,p.y); CGContextStrokePath(ctx); return; }
    if (pts.count < 2) return;
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, pts[0].CGPointValue.x, pts[0].CGPointValue.y);
    for (NSUInteger i = 1; i < pts.count; i++)
        CGContextAddLineToPoint(ctx, pts[i].CGPointValue.x, pts[i].CGPointValue.y);
    CGContextStrokePath(ctx);
}

// Arrow = shaft + two head strokes. (Mirrors drawArrowFrom:to:color:lineWidth:inContext:)
- (void)drawArrowFrom:(CGPoint)from to:(CGPoint)to color:(UIColor *)color
            lineWidth:(CGFloat)w inContext:(CGContextRef)ctx {
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, from.x, from.y);
    CGContextAddLineToPoint(ctx, to.x, to.y);
    CGContextStrokePath(ctx);

    CGFloat angle = atan2(to.y - from.y, to.x - from.x);
    CGFloat headLen = MAX(18.0, w * 3.0);
    CGFloat spread = M_PI / 7.0;
    for (CGFloat s = -1; s <= 1; s += 2) {
        CGPoint h = CGPointMake(to.x - headLen * cos(angle + s*spread),
                                to.y - headLen * sin(angle + s*spread));
        CGContextMoveToPoint(ctx, to.x, to.y);
        CGContextAddLineToPoint(ctx, h.x, h.y);
    }
    CGContextStrokePath(ctx);
}

// Mosaic: pixelate the source image under each trail point, cell by cell.
- (void)drawMosaicWithPoints:(NSArray<NSValue *> *)pts cell:(CGFloat)cell
                   inContext:(CGContextRef)ctx {
    for (NSValue *v in pts) {
        [self drawMosaicBlockAt:v.CGPointValue cell:cell inContext:ctx];
    }
}

- (void)drawMosaicBlockAt:(CGPoint)p cell:(CGFloat)cell inContext:(CGContextRef)ctx {
    // Snap to a grid so overlapping points share the same blocks.
    CGFloat radius = cell;
    CGFloat minX = floor((p.x - radius)/cell)*cell;
    CGFloat minY = floor((p.y - radius)/cell)*cell;
    for (CGFloat y = minY; y <= p.y + radius; y += cell) {
        for (CGFloat x = minX; x <= p.x + radius; x += cell) {
            UIColor *avg = [self averageColorOfSourceInRect:CGRectMake(x,y,cell,cell)];
            if (!avg) continue;
            CGContextSetFillColorWithColor(ctx, avg.CGColor);
            CGContextFillRect(ctx, CGRectMake(x,y,cell,cell));
        }
    }
}

// Sample the average colour of the shown image within a canvas-space rect.
- (UIColor *)averageColorOfSourceInRect:(CGRect)rect {
    if (!self.sourceImage || CGRectIsEmpty(self.imageDisplayRect)) return nil;
    if (!CGRectIntersectsRect(rect, self.imageDisplayRect)) return nil;
    // Map canvas rect -> image pixel rect.
    CGFloat sx = CGImageGetWidth(self.sourceImage.CGImage)  / self.imageDisplayRect.size.width;
    CGFloat sy = CGImageGetHeight(self.sourceImage.CGImage) / self.imageDisplayRect.size.height;
    CGRect img = CGRectMake((rect.origin.x - self.imageDisplayRect.origin.x)*sx,
                            (rect.origin.y - self.imageDisplayRect.origin.y)*sy,
                            rect.size.width*sx, rect.size.height*sy);
    CGImageRef cg = CGImageCreateWithImageInRect(self.sourceImage.CGImage, img);
    if (!cg) return nil;
    // 1x1 downscale = average.
    unsigned char px[4] = {0,0,0,0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px,1,1,8,4,cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(c, CGRectMake(0,0,1,1), cg);
    CGContextRelease(c); CGColorSpaceRelease(cs); CGImageRelease(cg);
    return [UIColor colorWithRed:px[0]/255.0 green:px[1]/255.0
                            blue:px[2]/255.0 alpha:1.0];
}

// Magnifier: circular region drawn scaled-up from the source image.
- (void)drawMagnifierItem:(RSMarkupAnnotationItem *)item inContext:(CGContextRef)ctx {
    CGRect r = [self rectFrom:item.startPoint to:item.endPoint];
    CGFloat d = MAX(r.size.width, r.size.height);
    if (d < 8) return;
    CGRect circle = CGRectMake(CGRectGetMidX(r)-d/2, CGRectGetMidY(r)-d/2, d, d);
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, circle);
    CGContextClip(ctx);
    // Draw the source image scaled by magnifyScale, centered on the circle.
    CGFloat s = item.magnifyScale;
    CGRect dst = self.imageDisplayRect;
    CGRect scaled = CGRectMake(CGRectGetMidX(circle) - (CGRectGetMidX(circle)-dst.origin.x)*s,
                               CGRectGetMidY(circle) - (CGRectGetMidY(circle)-dst.origin.y)*s,
                               dst.size.width*s, dst.size.height*s);
    [self.sourceImage drawInRect:scaled];
    CGContextRestoreGState(ctx);
    CGContextSetStrokeColorWithColor(ctx, item.color.CGColor);
    CGContextSetLineWidth(ctx, item.lineWidth);
    CGContextStrokeEllipseInRect(ctx, circle);
}

#pragma mark - Highlight (1.6 新增：聚光灯式高亮)

// 圆角高亮区的圆角半径（据 1.6 文案"圆角"）。
static const CGFloat kHighlightCornerRadius = 12.0;

// 全屏压暗 + 挖空所有高亮区 → 形成"选中区亮、周边半透明"的聚光灯效果。
// 对应原插件 drawHighlightMaskInContext:。
- (void)drawHighlightMaskInContext:(CGContextRef)ctx {
    CGContextSaveGState(ctx);
    CGContextBeginTransparencyLayer(ctx, NULL);
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0 alpha:0.55].CGColor);
    CGContextFillRect(ctx, self.bounds);
    CGContextSetBlendMode(ctx, kCGBlendModeClear);
    for (RSMarkupAnnotationItem *item in self.items) {
        if (item.type != RSMarkupDrawModeHighlight) continue;
        CGRect r = [self rectFrom:item.startPoint to:item.endPoint];
        [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:kHighlightCornerRadius] fill];
    }
    CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);
}

// 把单个高亮区的圆角路径加进遮罩路径（供 even-odd 挖空）。
// 对应原插件 drawHighlightMaskWithItem:inContext: 的职责（这里聚合进上面的方法）。
- (void)addHighlightHolePath:(CGMutablePathRef)path forItem:(RSMarkupAnnotationItem *)item {
    CGRect r = [self rectFrom:item.startPoint to:item.endPoint];
    if (CGRectIsEmpty(r)) return;
    UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:r
                                                 cornerRadius:kHighlightCornerRadius];
    CGPathAddPath(path, NULL, bp.CGPath);
}

// 单区版本（保留与原插件同名 selector，便于对照）：压暗全屏并只挖这一个区。
- (void)drawHighlightMaskWithItem:(RSMarkupAnnotationItem *)item inContext:(CGContextRef)ctx {
    CGContextSaveGState(ctx);
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, self.bounds);
    [self addHighlightHolePath:path forItem:item];
    CGContextAddPath(ctx, path);
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.0 alpha:0.55].CGColor);
    CGContextEOFillPath(ctx);
    CGPathRelease(path);
    CGContextRestoreGState(ctx);
}

// 给高亮区画圆角边框。对应原插件 drawHighlightBorderItem:inContext:。
- (void)drawHighlightBorderItem:(RSMarkupAnnotationItem *)item inContext:(CGContextRef)ctx {
    CGRect r = [self rectFrom:item.startPoint to:item.endPoint];
    if (CGRectIsEmpty(r)) return;
    UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:r
                                                 cornerRadius:kHighlightCornerRadius];
    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, bp.CGPath);
    CGContextSetStrokeColorWithColor(ctx, item.color.CGColor);
    CGContextSetLineWidth(ctx, MAX(2.0, item.lineWidth));
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);
}

#pragma mark - Export

- (UIImage *)renderedImage {
    if (!self.sourceImage || CGRectIsEmpty(self.imageDisplayRect)) return self.sourceImage;
    CGSize sz = self.sourceImage ? self.sourceImage.size : self.bounds.size;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = self.sourceImage.scale ?: [UIScreen mainScreen].scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        [self.sourceImage drawInRect:CGRectMake(0,0,sz.width,sz.height)];
        // Scale canvas-space marks into image space.
        CGFloat sx = sz.width  / self.imageDisplayRect.size.width;
        CGFloat sy = sz.height / self.imageDisplayRect.size.height;
        CGContextRef ctx = rc.CGContext;
        CGContextTranslateCTM(ctx, -self.imageDisplayRect.origin.x*sx,
                                   -self.imageDisplayRect.origin.y*sy);
        CGContextScaleCTM(ctx, sx, sy);
        [self drawRect:self.bounds];
    }];
}

@end
