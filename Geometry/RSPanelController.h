// Included with a distinct class name by each of the two injected binaries.
#import "RSOrientation.h"
@interface RS_PANEL_CONTROLLER : UIViewController
@property(strong) UIView *canvas;
@property UIInterfaceOrientation orientation;
@property(copy) void (^onLayout)(void);
@end
@implementation RS_PANEL_CONTROLLER
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
