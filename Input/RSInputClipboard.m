// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
// Prompt interaction adapted from Kayoko, GPL-3.0; see THIRD_PARTY.md.
#import "RSInputClipboard.h"
#import "RSInputInterface.h"
#import "RSInputStore.h"
#import "RSInputOptions.h"
#import "RSInputAnchoredMenuView.h"
#import <notify.h>
#import <objc/message.h>

static BOOL RSInputLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance"), locked = NSSelectorFromString(@"isUILocked");
    if (![cls respondsToSelector:shared]) return YES;
    id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    return ![manager respondsToSelector:locked] || ((BOOL (*)(id, SEL))objc_msgSend)(manager, locked);
}
static UIColor *RSInputHexColor(NSString *hex) {
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 255)/255.0 green:((rgb >> 8) & 255)/255.0 blue:(rgb & 255)/255.0 alpha:1];
}
void RSInputOpenSearchEngine(NSDictionary *engine, NSString *text) {
    NSURL *url = RSInputSearchURL(engine[@"engine"], text);
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
void RSInputOpenSearch(NSString *text) { RSInputOpenSearchEngine(RSInputSearchEngines(RSInputConfig()).firstObject, text); }

@interface RSInputPromptWindow : UIWindow
@property(weak) UIView *interactiveView;
@end
@implementation RSInputPromptWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return self.interactiveView && (hit == self.interactiveView || [hit isDescendantOfView:self.interactiveView]) ? hit : nil;
}
@end
@interface RSInputPromptButton : UIButton
@property(strong) CAGradientLayer *gradient;
@property CGFloat speed;
@property BOOL animations;
@end
@implementation RSInputPromptButton
- (void)layoutSubviews { [super layoutSubviews]; self.gradient.frame = self.bounds; self.gradient.cornerRadius = self.layer.cornerRadius; }
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:self.animations ? (highlighted ? 0.42 : 0.38) / MAX(0.5, self.speed) : 0
        delay:0 usingSpringWithDamping:highlighted ? 0.58 : 0.64 initialSpringVelocity:highlighted ? 3 : 1.2
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:^{ self.transform = highlighted ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity; } completion:nil];
}
@end
@interface RSInputClipboardPrompt : NSObject
@property(strong) RSInputPromptWindow *window;
@property(strong) RSInputPromptButton *button;
@property(strong) RSInputAnchoredMenuView *menu;
@property(copy) NSString *text;
@property(strong) NSDictionary *options;
@property(strong) NSTimer *timer;
@property NSUInteger epoch;
@property NSInteger changeCount;
- (void)capture;
- (void)hide;
@end
@implementation RSInputClipboardPrompt
- (void)hide {
    [self.timer invalidate]; self.timer = nil;
    RSInputPromptWindow *window = self.window;
    RSInputPromptButton *button = self.button;
    BOOL animate = button.animations && !self.menu && !RSInputLocked();
    self.window = nil; self.button = nil; self.menu = nil; self.text = nil;
    window.userInteractionEnabled = NO;
    [UIView animateWithDuration:animate ? 0.16 / MAX(0.5, button.speed) : 0 animations:^{
        button.alpha = 0; button.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(__unused BOOL finished) { window.hidden = YES; }];
}
- (void)scheduleHide {
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:[self.options[@"duration"] doubleValue] target:self selector:@selector(hide) userInfo:nil repeats:NO];
}
- (void)tap {
    NSString *text = self.text;
    [self hide];
    if (!RSInputLocked()) RSInputOpenCopiedText(text);
}
- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    if (RSInputLocked()) { [self hide]; return; }
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self.timer invalidate]; self.timer = nil;
        NSString *text = self.text;
        RSInputAnchoredMenuView *menu = [RSInputAnchoredMenuView new];
        menu.menuWidth = 180; menu.centersTitles = YES; menu.presentsBelowSource = YES;
        __weak RSInputClipboardPrompt *weakSelf = self;
        for (NSDictionary *engine in RSInputSearchEngines(RSInputConfig())) {
            [menu addItemWithTitle:engine[@"name"] image:[UIImage systemImageNamed:@"magnifyingglass"] destructive:NO handler:^{
                [weakSelf hide]; if (!RSInputLocked()) RSInputOpenSearchEngine(engine, text);
            }];
        }
        for (NSDictionary *action in RSInputVisibleActions(@"clipboardHiddenPersonas")) {
            [menu addItemWithTitle:action[@"title"] image:[UIImage systemImageNamed:@"sparkles"] destructive:NO handler:^{
                [weakSelf hide]; if (!RSInputLocked()) RSInputRunCopiedAction(action, text, ^(NSString *result) { RSInputOpenSearch(result); });
            }];
        }
        menu.onDismiss = ^{
            RSInputClipboardPrompt *strong = weakSelf;
            strong.menu = nil;
            strong.window.interactiveView = strong.button;
            if (strong.window) [strong scheduleHide];
        };
        self.menu = menu;
        self.window.interactiveView = menu;
        [menu presentFromView:self.button inView:self.window.rootViewController.view];
        RSInputSelectionFeedback();
    }
    [self.menu trackGestureRecognizer:gesture];
}
- (void)capture {
    NSUInteger epoch = ++self.epoch;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (epoch != self.epoch) return;
        UIPasteboard *pasteboard = UIPasteboard.generalPasteboard;
        if (self.changeCount == pasteboard.changeCount) return;
        self.changeCount = pasteboard.changeCount;
        [self hide];
        self.options = RSInputPromptOptions(RSInputConfig());
        if (RSInputLocked() || RSInputIsPanelVisible() || ![self.options[@"enabled"] boolValue] ||
            [pasteboard containsPasteboardTypes:@[@"com.moxuan.regionshot.input.internal"]]) return;
        NSString *text = pasteboard.string;
        if (!text.length || text.length > 24000) return;
        self.text = text;
        UIWindowScene *scene = nil;
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
            if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) { scene = (id)candidate; break; }
        self.window = scene ? [[RSInputPromptWindow alloc] initWithWindowScene:scene] : [[RSInputPromptWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.window.frame = UIScreen.mainScreen.bounds;
        self.window.backgroundColor = UIColor.clearColor;
        self.window.windowLevel = CGFLOAT_MAX;
        self.window.rootViewController = [UIViewController new];
        UIView *host = self.window.rootViewController.view;
        host.backgroundColor = UIColor.clearColor;
        RSInputPromptButton *button = [RSInputPromptButton buttonWithType:UIButtonTypeCustom];
        self.button = button;
        CGFloat scale = [self.options[@"size"] doubleValue] / 100;
        button.animations = [self.options[@"animations"] boolValue];
        button.speed = [self.options[@"animationSpeed"] doubleValue];
        button.layer.cornerRadius = 22 * scale;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOpacity = 0.18; button.layer.shadowRadius = 6; button.layer.shadowOffset = CGSizeMake(0, 3);
        button.gradient = [CAGradientLayer layer];
        UIColor *start = RSInputHexColor(self.options[@"startColor"]);
        button.gradient.colors = [self.options[@"gradient"] boolValue] ? @[(id)start.CGColor, (id)RSInputHexColor(self.options[@"middleColor"]).CGColor, (id)RSInputHexColor(self.options[@"endColor"]).CGColor] : @[(id)start.CGColor, (id)start.CGColor];
        button.gradient.startPoint = CGPointMake(0, 0.5); button.gradient.endPoint = CGPointMake(1, 0.5);
        [button.layer insertSublayer:button.gradient atIndex:0];
        [button setTitle:@"分词" forState:UIControlStateNormal];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        button.tintColor = UIColor.whiteColor;
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCallout] scaledFontForFont:[UIFont systemFontOfSize:16 * scale weight:UIFontWeightSemibold]];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.5;
        button.titleLabel.numberOfLines = 1;
        button.titleLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
        button.accessibilityLabel = @"分词";
        button.accessibilityHint = @"轻按分词，长按打开搜索引擎和 AI 人设";
        button.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc] initWithName:@"搜索复制文字" actionHandler:^BOOL(__unused UIAccessibilityCustomAction *action) {
            NSString *copied = self.text; [self hide]; if (!RSInputLocked()) RSInputOpenSearch(copied); return YES;
        }]];
        [button addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        [button addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [host addSubview:button];
        NSLayoutConstraint *vertical = [NSLayoutConstraint constraintWithItem:button attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:host attribute:NSLayoutAttributeBottom multiplier:[self.options[@"height"] doubleValue]/100 constant:0];
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:72 * scale], [button.heightAnchor constraintEqualToConstant:44 * scale],
            [button.trailingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.trailingAnchor constant:-16], vertical]];
        self.window.interactiveView = button;
        self.window.hidden = NO;
        [self scheduleHide];
    });
}
@end
void RSInputStartClipboardPrompt(void) {
    static RSInputClipboardPrompt *prompt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prompt = [RSInputClipboardPrompt new];
        prompt.changeCount = UIPasteboard.generalPasteboard.changeCount;
        int token;
        notify_register_dispatch("com.apple.pasteboard.notify.changed", &token, dispatch_get_main_queue(), ^(__unused int value) { [prompt capture]; });
        notify_register_dispatch("com.apple.springboard.lockstate", &token, dispatch_get_main_queue(), ^(__unused int value) {
            prompt.epoch++; [prompt hide]; RSInputClosePanel();
        });
        [NSNotificationCenter.defaultCenter addObserver:prompt selector:@selector(hide) name:UIApplicationProtectedDataWillBecomeUnavailable object:nil];
    });
}
