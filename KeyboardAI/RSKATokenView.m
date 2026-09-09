#import "RSKATokenView.h"
#import "RSKACore.h"
#import "RSKAInterface.h"

// Use the same UILabel measurement and padding for sizing and rendering.
@interface RSKATokenCell : UICollectionViewCell
@property(strong) UILabel *label;
@end
@implementation RSKATokenCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _label = [UILabel new];
        _label.font = [UIFont systemFontOfSize:12];
        _label.numberOfLines = 0;
        _label.lineBreakMode = NSLineBreakByCharWrapping;
        _label.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_label];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.label.frame = UIEdgeInsetsInsetRect(self.contentView.bounds, UIEdgeInsetsMake(3, 4, 3, 4));
}
@end

@interface RSKATokenView () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
@property(strong) NSMutableArray<NSString *> *pieces;
@property(strong) NSMutableIndexSet *chosen;
@property(strong) NSArray<NSValue *> *sizes;
@property CGFloat measuredWidth;
@property CGFloat reportedHeight;
@property(strong) UIPanGestureRecognizer *paint;
@property(strong) UILongPressGestureRecognizer *back;
@property(strong) CADisplayLink *scrollLink;
@property(strong) NSIndexSet *paintBaseline;
@property NSUInteger anchorIndex;
@property NSUInteger lastIndex;
@property BOOL selecting;
@end
@implementation RSKATokenView
- (instancetype)initWithPieces:(NSArray<NSString *> *)pieces {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 6;
    layout.minimumLineSpacing = 6;
    layout.sectionInset = UIEdgeInsetsMake(0, 0, 0, 36);
    if ((self = [super initWithFrame:CGRectZero collectionViewLayout:layout])) {
        self.pieces = [pieces mutableCopy];
        self.chosen = [NSMutableIndexSet indexSet];
        self.dataSource = self;
        self.delegate = self;
        self.backgroundColor = UIColor.clearColor;
        self.alwaysBounceVertical = YES;
        self.showsVerticalScrollIndicator = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.lastIndex = NSNotFound;
        [self registerClass:RSKATokenCell.class forCellWithReuseIdentifier:@"piece"];
        self.paint = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(paintWords:)];
        self.paint.maximumNumberOfTouches = 1;
        self.paint.delegate = self;
        [self addGestureRecognizer:self.paint];
        [self.panGestureRecognizer requireGestureRecognizerToFail:self.paint];
        UILongPressGestureRecognizer *split = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(splitWord:)];
        split.minimumPressDuration = 0.65;
        split.allowableMovement = 8;
        [self addGestureRecognizer:split];
        self.back = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(gutterLongPress:)];
        self.back.delegate = self;
        [self addGestureRecognizer:self.back];
    }
    return self;
}
- (void)gutterLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan && self.onGutterLongPress)
        self.onGutterLongPress();
}
- (NSString *)displayPiece:(NSString *)piece {
    if (!RSKATrim(piece).length) return [piece containsString:@"\n"] ? @"↵" : @"";
    return [piece stringByReplacingOccurrencesOfString:@"\n" withString:@"↵"];
}
- (void)layoutSubviews {
    CGFloat width = floor(self.bounds.size.width);
    if (width > 0 && width != self.measuredWidth) {
        self.measuredWidth = width;
        self.sizes = nil;
        [self.collectionViewLayout invalidateLayout];
    }
    [super layoutSubviews];
    CGFloat height = self.collectionViewLayout.collectionViewContentSize.height;
    if (height != self.reportedHeight) {
        self.reportedHeight = height;
        __weak RSKATokenView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            RSKATokenView *view = weakSelf;
            if (view.window && view.onLayoutChanged) view.onLayoutChanged();
        });
    }
}
- (void)measurePieces {
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionViewLayout;
    CGFloat limit = MAX(1, floor(self.bounds.size.width) - layout.sectionInset.left - layout.sectionInset.right);
    UILabel *label = ((RSKATokenCell *)[[RSKATokenCell alloc] initWithFrame:CGRectZero]).label;
    NSMutableArray *sizes = [NSMutableArray arrayWithCapacity:self.pieces.count];
    for (NSString *piece in self.pieces) {
        label.text = [self displayPiece:piece];
        CGSize measured = [label sizeThatFits:CGSizeMake(MAX(1, limit - 10), CGFLOAT_MAX)];
        [sizes addObject:[NSValue valueWithCGSize:CGSizeMake(MIN(limit, MAX(24, ceil(measured.width) + 10)), MAX(24, ceil(measured.height) + 8))]];
    }
    self.sizes = sizes;
}
- (NSInteger)collectionView:(__unused UICollectionView *)collectionView numberOfItemsInSection:(__unused NSInteger)section { return self.pieces.count; }
- (CGSize)collectionView:(__unused UICollectionView *)collectionView layout:(__unused UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    if (!self.sizes) [self measurePieces];
    return self.sizes[path.item].CGSizeValue;
}
- (void)configureCell:(UICollectionViewCell *)cell index:(NSUInteger)index {
    BOOL selected = [self.chosen containsIndex:index];
    UILabel *label = ((RSKATokenCell *)cell).label;
    label.text = [self displayPiece:self.pieces[index]];
    label.textColor = selected ? UIColor.whiteColor : UIColor.labelColor;
    cell.backgroundColor = selected ? UIColor.systemBlueColor : UIColor.secondarySystemGroupedBackgroundColor;
    cell.layer.cornerRadius = 8;
    cell.layer.borderWidth = selected ? 0 : 0.5;
    cell.layer.borderColor = UIColor.separatorColor.CGColor;
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.accessibilityLabel = label.text.length ? label.text : @"空格";
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    __weak RSKATokenView *weakSelf = self;
    UIAccessibilityCustomAction *split = [[UIAccessibilityCustomAction alloc] initWithName:@"拆成单字" actionHandler:^BOOL(__unused UIAccessibilityCustomAction *action) {
        return [weakSelf splitAtIndex:index];
    }];
    cell.accessibilityCustomActions = @[split];
    cell.isAccessibilityElement = YES;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"piece" forIndexPath:path];
    [self configureCell:cell index:path.item];
    return cell;
}
- (void)notifySelection {
    for (NSIndexPath *path in self.indexPathsForVisibleItems) {
        UICollectionViewCell *cell = [self cellForItemAtIndexPath:path];
        if ([self.chosen containsIndex:path.item] != ((cell.accessibilityTraits & UIAccessibilityTraitSelected) != 0))
            [self configureCell:cell index:path.item];
    }
    if (self.onSelectionChanged) self.onSelectionChanged();
}
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)path {
    [collectionView deselectItemAtIndexPath:path animated:NO];
    RSKAPaintSelection(self.chosen, path.item, path.item, ![self.chosen containsIndex:path.item]);
    [self notifySelection];
    RSKASelectionFeedback();
}
- (BOOL)hasSelection { return self.chosen.count > 0; }
- (void)clearSelection {
    if (!self.chosen.count) return;
    [self.chosen removeAllIndexes];
    [self notifySelection];
    RSKASelectionFeedback();
}
- (NSString *)selectedText {
    NSMutableString *text = [NSMutableString string];
    [self.chosen enumerateIndexesUsingBlock:^(NSUInteger index, __unused BOOL *stop) { [text appendString:self.pieces[index]]; }];
    return text;
}
- (BOOL)splitAtIndex:(NSUInteger)index {
    if (!RSKASplitPiece(self.pieces, self.chosen, index)) return NO;
    self.sizes = nil;
    [self reloadData];
    [self layoutIfNeeded];
    [self scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0] atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
    if (self.onSelectionChanged) self.onSelectionChanged();
    RSKASelectionFeedback();
    return YES;
}
- (void)splitWord:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *path = [self indexPathForItemAtPoint:[gesture locationInView:self]];
    if (path) [self splitAtIndex:path.item];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == self.back)
        return [gesture locationInView:self].x >= self.bounds.size.width - 36;
    if (gesture != self.paint) return [super gestureRecognizerShouldBegin:gesture];
    CGPoint point = [self.paint locationInView:self], translation = [self.paint translationInView:self];
    return [self indexPathNearPoint:CGPointMake(point.x - translation.x, point.y - translation.y)] != nil;
}
- (NSIndexPath *)indexPathNearPoint:(CGPoint)point {
    if (point.x >= self.bounds.size.width - 36) return nil;
    NSIndexPath *path = [self indexPathForItemAtPoint:point];
    if (path) return path;
    for (NSIndexPath *visible in self.indexPathsForVisibleItems)
        if (CGRectContainsPoint(CGRectInset([self layoutAttributesForItemAtIndexPath:visible].frame, -4, -4), point))
            return visible;
    return nil;
}
- (void)paintAtPoint:(CGPoint)point {
    NSIndexPath *path = [self indexPathNearPoint:point];
    if (!path || self.lastIndex == NSNotFound || (NSUInteger)path.item == self.lastIndex) return;
    RSKAUpdatePaintSelection(self.chosen, self.paintBaseline, self.anchorIndex, path.item, self.selecting);
    self.lastIndex = path.item;
    [self notifySelection];
}
- (void)paintWords:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint translation = [gesture translationInView:self];
        NSIndexPath *first = [self indexPathNearPoint:CGPointMake(point.x - translation.x, point.y - translation.y)];
        if (!first) return;
        self.paintBaseline = [self.chosen copy];
        self.anchorIndex = first.item;
        self.lastIndex = first.item;
        self.selecting = ![self.chosen containsIndex:first.item];
        RSKAUpdatePaintSelection(self.chosen, self.paintBaseline, self.anchorIndex, first.item, self.selecting);
        [self notifySelection];
        self.scrollLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(scrollWhilePainting:)];
        [self.scrollLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        RSKASelectionFeedback();
    }
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) [self paintAtPoint:point];
    else {
        if (gesture.state == UIGestureRecognizerStateEnded) [self paintAtPoint:point];
        [self.scrollLink invalidate]; self.scrollLink = nil;
        self.paintBaseline = nil; self.lastIndex = NSNotFound;
    }
}
- (void)scrollWhilePainting:(CADisplayLink *)link {
    CGPoint point = [self.paint locationInView:self];
    CGFloat y = point.y - self.contentOffset.y, height = self.bounds.size.height;
    CGFloat velocity = y < 36 ? -240 : y > height - 36 ? 240 : 0;
    CGFloat maximum = MAX(0, self.contentSize.height - height);
    CGFloat offset = MIN(maximum, MAX(0, self.contentOffset.y + velocity * (link.targetTimestamp - link.timestamp)));
    if (offset != self.contentOffset.y) {
        self.contentOffset = CGPointMake(self.contentOffset.x, offset);
        [self layoutIfNeeded];
        [self paintAtPoint:[self.paint locationInView:self]];
    }
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) { [self.scrollLink invalidate]; self.scrollLink = nil; }
}
@end
