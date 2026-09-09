// Included with a distinct class name by each of the two injected binaries.
#import "RSOrientation.h"
@interface RS_PANEL_CONTROLLER : UIViewController <UIGestureRecognizerDelegate>
@property(strong) UIView *canvas;
@property UIInterfaceOrientation orientation;
@property(copy) void (^onLayout)(void);
@property CGPoint temporaryOffset;
- (void)attachDragHandleToPanel:(UIView *)panel;
@end
@implementation RS_PANEL_CONTROLLER
- (void)attachDragHandleToPanel:(UIView *)panel {
    UIView *handle = [UIView new];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.userInteractionEnabled = NO;
    handle.accessibilityLabel = @"拖动窗口";
    [panel addSubview:handle];
    [NSLayoutConstraint activateConstraints:@[
        [handle.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [handle.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
        [handle.widthAnchor constraintEqualToAnchor:panel.widthAnchor constant:-24],
        [handle.heightAnchor constraintEqualToConstant:32]]];
    UIView *line = [UIView new];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = UIColor.tertiaryLabelColor; line.layer.cornerRadius = 1.5;
    line.userInteractionEnabled = NO; [handle addSubview:line];
    [NSLayoutConstraint activateConstraints:@[[line.centerXAnchor constraintEqualToAnchor:handle.centerXAnchor], [line.topAnchor constraintEqualToAnchor:handle.topAnchor constant:5], [line.widthAnchor constraintEqualToConstant:32], [line.heightAnchor constraintEqualToConstant:3]]];
    UIPanGestureRecognizer *topDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    topDrag.name = @"rs.topDrag"; topDrag.delegate = self;
    [panel addGestureRecognizer:topDrag];
    UIView *bottom = [UIView new];
    bottom.translatesAutoresizingMaskIntoConstraints = NO;
    bottom.userInteractionEnabled = NO;
    bottom.accessibilityLabel = @"上下移动窗口";
    [panel addSubview:bottom];
    [NSLayoutConstraint activateConstraints:@[
        [bottom.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
        [bottom.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [bottom.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [bottom.heightAnchor constraintEqualToConstant:28]]];
    UIPanGestureRecognizer *bottomDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanelVertically:)];
    bottomDrag.name = @"rs.bottomDrag"; bottomDrag.delegate = self;
    [panel addGestureRecognizer:bottomDrag];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:gesture.view];
    CGFloat width = gesture.view.bounds.size.width, height = gesture.view.bounds.size.height;
    if (point.x < 12 || point.x > width - 12) return NO;
    return [gesture.name isEqualToString:@"rs.topDrag"] ? point.y <= 32 : point.y >= height - 28;
}
- (void)dragPanelVertically:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self.canvas];
    self.temporaryOffset = CGPointMake(self.temporaryOffset.x, self.temporaryOffset.y + delta.y);
    [gesture setTranslation:CGPointZero inView:self.canvas];
    if (self.onLayout) self.onLayout();
}
- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self.canvas];
    self.temporaryOffset = CGPointMake(self.temporaryOffset.x+delta.x, self.temporaryOffset.y+delta.y);
    [gesture setTranslation:CGPointZero inView:self.canvas];
    if (self.onLayout) self.onLayout();
}
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.clearColor;
    self.canvas = [UIView new]; [self.view addSubview:self.canvas];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize physical = UIScreen.mainScreen.fixedCoordinateSpace.bounds.size;
    BOOL landscape = UIInterfaceOrientationIsLandscape(self.orientation);
    CGSize visible = landscape ? CGSizeMake(physical.height, physical.width) : physical;
    self.canvas.bounds = (CGRect){CGPointZero, visible};
    self.canvas.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
    CGFloat angle = self.orientation == UIInterfaceOrientationLandscapeLeft ? -M_PI_2 : self.orientation == UIInterfaceOrientationLandscapeRight ? M_PI_2 : 0;
    self.canvas.transform = CGAffineTransformMakeRotation(angle);
    if (self.onLayout) self.onLayout();
}
@end
#undef RS_PANEL_CONTROLLER
