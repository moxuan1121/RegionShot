// Included with a distinct class name by each of the two injected binaries.
#import "RSOrientation.h"
@interface RS_PANEL_CONTROLLER : UIViewController
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
    handle.accessibilityLabel = @"拖动窗口";
    [panel addSubview:handle];
    [NSLayoutConstraint activateConstraints:@[
        [handle.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [handle.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
        [handle.widthAnchor constraintEqualToConstant:90],
        [handle.heightAnchor constraintEqualToConstant:22]]];
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(29,5,32,3)];
    line.backgroundColor = UIColor.tertiaryLabelColor; line.layer.cornerRadius = 1.5;
    line.userInteractionEnabled = NO; [handle addSubview:line];
    [handle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];
    UIView *bottom = [UIView new];
    bottom.translatesAutoresizingMaskIntoConstraints = NO;
    bottom.accessibilityLabel = @"上下移动窗口";
    [panel addSubview:bottom];
    [NSLayoutConstraint activateConstraints:@[
        [bottom.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
        [bottom.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [bottom.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [bottom.heightAnchor constraintEqualToConstant:10]]];
    [bottom addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanelVertically:)]];
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
