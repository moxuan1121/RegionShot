#import "../Geometry/RSPopupLayout.h"
#import "../Geometry/RSWindowAnimation.h"
#define RS_PANEL_CONTROLLER RSKAPanelController
#import "../Geometry/RSPanelController.h"
// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import "RSKAInterface.h"
#import "RSKACore.h"
#import "RSKATokenView.h"
#import "RSKAOptions.h"
#import "RSKAAnchoredMenuView.h"
#import "../Geometry/RSOrientation.h"
#import "../Input/RSInputStore.h"
static NSDictionary *RSKAConfig(void) { return RSInputConfig(); }
static void RSKAOpenSearchEngine(NSDictionary *engine, NSString *text) {
    NSURL *url = RSKASearchURL(engine[@"engine"], text);
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
static void RSKAOpenSearch(NSString *text) { RSKAOpenSearchEngine(RSKASearchEngines(RSKAConfig()).firstObject, text); }
void RSKASelectionFeedback(void) {
    static UISelectionFeedbackGenerator *feedback;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ feedback = [UISelectionFeedbackGenerator new]; });
    [feedback selectionChanged];
    [feedback prepare];
}

static UIWindow *RSKAWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (window.isKeyWindow) return window;
    }
    return nil;
}

static UIWindowLevel RSKAPanelWindowLevel(NSDictionary *options, NSString *key) {
    double priority = [options[key] doubleValue];
    return priority >= 1000000000 ? CGFLOAT_MAX : (UIWindowLevel)priority;
}

@interface RSKACard : UIView
@end
@implementation RSKACard
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.layer.cornerRadius].CGPath;
}
@end

@interface RSKAPanelWindow : UIWindow
@end
@implementation RSKAPanelWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view || hit == ((RSKAPanelController *)self.rootViewController).canvas ? nil : hit;
}
@end

@interface RSKAPanel : NSObject
@property(strong) UIView *panel;
@property(strong) UIWindow *overlayWindow;
@property(weak) UIWindow *previousWindow;
@property(strong) UITextView *textView;
@property(strong) UIStackView *contentStack;
@property(strong) UIStackView *header;
@property(strong) RSKATokenView *tokenView;
@property(strong) UIButton *backButton;
@property(strong) UIButton *replaceButton;
@property(strong) UIButton *clipboardButton;
@property(strong) RSKAAnchoredMenuView *searchMenu;
@property(copy) NSString *result;
@property BOOL generating;
@property BOOL completedResult;
@property(strong) UILabel *statusLabel;
@property(strong) UIActivityIndicatorView *spinner;
@property(strong) NSLayoutConstraint *heightConstraint;
@property(strong) NSDictionary *windowOptions;
@property BOOL resizing;
@property(strong) NSLayoutConstraint *panelTop;
@property(strong) NSLayoutConstraint *panelLeading;
@property(strong) NSLayoutConstraint *panelWidth;
@property(copy) dispatch_block_t onClose;
- (void)close;
- (void)enterTokens;
@end
@implementation RSKAPanel
- (instancetype)init {
    if ((self = [super init])) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateOrientation:) name:@"com.moxuan.regionshot.orientation.target" object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(close) name:UIApplicationProtectedDataWillBecomeUnavailable object:nil];
    }
    return self;
}
- (void)updateOrientation:(NSNotification *)note {
    if (!self.overlayWindow) return;
    ((RSKAPanelController *)self.overlayWindow.rootViewController).orientation = note.userInfo[@"orientation"] ? [note.userInfo[@"orientation"] integerValue] : RSActiveOrientation(self.overlayWindow.windowScene);
    [self.overlayWindow.rootViewController.view setNeedsLayout];
    [self resizePanel];
    [self.searchMenu setNeedsLayout];
}
- (void)buttonPressed {
    static UIImpactFeedbackGenerator *feedback;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium]; });
    [feedback impactOccurred];
    [feedback prepare];
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = ([title isEqualToString:@"替换"] || [title isEqualToString:@"搜索"]) ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = title;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    configuration.background.cornerRadius = 12;
    configuration.baseBackgroundColor = UIColor.systemBlueColor;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(11, 6, 11, 6);
    configuration.image = [UIImage systemImageNamed:[title isEqualToString:@"搜索"] ? @"magnifyingglass" : [title isEqualToString:@"替换"] ? @"arrow.left.arrow.right" : [title isEqualToString:@"复制"] ? @"doc.on.doc" : @"xmark"];
    configuration.imagePadding = 5;
    configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    button.configuration = configuration;
    button.layer.cornerRadius = 12;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.clipsToBounds = YES;
    button.configurationUpdateHandler = ^(UIButton *control) {
        control.alpha = control.enabled ? (control.highlighted ? 0.65 : 1.0) : 0.38;
        control.transform = control.highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
    };
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(buttonPressed) forControlEvents:UIControlEventTouchDown];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}
- (BOOL)show {
    self.windowOptions = RSKAPromptOptions(RSKAConfig());
    UIWindow *window = RSKAWindow();
    if (!window) return NO;
    UIInterfaceOrientation openingOrientation = RSActiveOrientation(window.windowScene);
    self.previousWindow = window;
    self.overlayWindow = window.windowScene ? [[RSKAPanelWindow alloc] initWithWindowScene:window.windowScene] : [[RSKAPanelWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.overlayWindow.frame = UIScreen.mainScreen.fixedCoordinateSpace.bounds;
    RSKAPanelController *controller = [RSKAPanelController new];
    controller.orientation = openingOrientation;
    self.overlayWindow.rootViewController = controller;
    RSApplyWindowOrientation(self.overlayWindow, UIInterfaceOrientationPortrait);
    __weak typeof(self) weakSelf = self;
    controller.onLayout = ^{ [weakSelf resizePanel]; };
    self.overlayWindow.backgroundColor = UIColor.clearColor; self.overlayWindow.opaque = NO;
    self.overlayWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.overlayWindow.windowLevel = RSKAPanelWindowLevel(self.windowOptions, @"aiWindowPriority");
    [self.overlayWindow makeKeyAndVisible];
    window = self.overlayWindow;
    UIView *panel = [RSKACard new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    panel.layer.cornerRadius = 20;
    panel.layer.cornerCurve = kCACornerCurveContinuous;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.18;
    panel.layer.shadowRadius = 18;
    panel.layer.shadowOffset = CGSizeMake(0, 7);
    self.panel = panel;
    UITextView *text = [UITextView new];
    text.editable = NO;
    text.selectable = NO; // Preserve the chat input's first responder while previewing.
    text.backgroundColor = UIColor.clearColor;
    text.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:17]];
    text.textColor = UIColor.labelColor;
    text.textContainerInset = UIEdgeInsetsMake(3, 0, 3, 0);
    text.textContainer.lineFragmentPadding = 0;
    text.showsVerticalScrollIndicator = NO;
    text.showsHorizontalScrollIndicator = NO;
    text.adjustsFontForContentSizeCategory = YES;
    text.accessibilityLabel = @"AI 处理结果";
    self.textView = text;
    [text addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tokenize:)]];
    self.replaceButton = [self button:@"搜索" action:@selector(searchResult)];
    {
        UILongPressGestureRecognizer *searchMenu = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showSearchMenu:)];
        searchMenu.minimumPressDuration = 0.35;
        [self.replaceButton addGestureRecognizer:searchMenu];
        self.replaceButton.accessibilityHint = @"轻按使用默认搜索引擎，长按选择搜索引擎";
    }
    self.clipboardButton = [self button:@"复制" action:@selector(copyResult)];
    UIButton *close = [self button:@"关闭" action:@selector(close)];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.replaceButton, self.clipboardButton, close]];
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.spacing = 8;
    self.statusLabel = [UILabel new];
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.text = @"AI 助手";
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backButton setTitle:@"返回全文" forState:UIControlStateNormal];
    [self.backButton addTarget:self action:@selector(leaveTokens) forControlEvents:UIControlEventTouchUpInside];
    self.backButton.hidden = YES;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[self.spinner, self.statusLabel, self.backButton]];
    self.header = header;
    header.spacing = 8;
    header.alignment = UIStackViewAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[header, text, buttons]];
    self.contentStack = stack;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    RSApplyWindowOrientation(window, UIInterfaceOrientationPortrait);
    [controller.view setNeedsLayout]; [controller.view layoutIfNeeded];
    UIView *host = controller.canvas;
    [host addSubview:panel];
    self.panelTop = [panel.topAnchor constraintEqualToAnchor:host.topAnchor constant:8];
    self.panelLeading = [panel.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:12];
    self.panelWidth = [panel.widthAnchor constraintEqualToConstant:300];
    self.heightConstraint = [panel.heightAnchor constraintEqualToConstant:160];
    self.heightConstraint.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        self.panelLeading, self.panelWidth,
        self.panelTop,
        self.heightConstraint,
        [panel.bottomAnchor constraintLessThanOrEqualToAnchor:host.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-10]
    ]];
    self.replaceButton.enabled = NO;
    self.clipboardButton.enabled = NO;
    [controller attachDragHandleToPanel:panel];
    RSOpenWindowSurface(self.panel);
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    return YES;
}
- (void)resizePanel {
    UIWindow *window = self.panel.window;
    if (!window || self.resizing) return;
    self.resizing = YES;
    UIView *canvas = ((RSKAPanelController *)window.rootViewController).canvas;
    BOOL landscape = UIInterfaceOrientationIsLandscape(((RSKAPanelController *)window.rootViewController).orientation);
    RSRectD placement = RSPopupFrame(canvas.bounds.size.width, canvas.bounds.size.height,
        UIScreen.mainScreen.fixedCoordinateSpace.bounds.size.width, landscape ? [self.windowOptions[@"panelPosition"] intValue] : 1,
        [self.windowOptions[landscape ? @"panelTopLandscape" : @"panelTop"] doubleValue], [self.windowOptions[@"panelHeight"] doubleValue]);
    RSKAPanelController *controller = (id)window.rootViewController;
    CGFloat baseX = placement.x, baseY = placement.y;
    placement.x = MIN(MAX(0, placement.x + controller.temporaryOffset.x), MAX(0, canvas.bounds.size.width - placement.width));
    placement.y = MIN(MAX(0, placement.y + controller.temporaryOffset.y), MAX(0, canvas.bounds.size.height - 100));
    controller.temporaryOffset = CGPointMake(placement.x-baseX, placement.y-baseY);
    self.panelTop.constant = placement.y; self.panelLeading.constant = placement.x; self.panelWidth.constant = placement.width;
    [window layoutIfNeeded];
    CGFloat available = MAX(0, canvas.bounds.size.height - placement.y - 12);
    self.heightConstraint.constant = RSPopupContentHeight(self.contentStack, self.tokenView ?: self.textView,
        MAX(1, placement.width - 24), available, [self.windowOptions[@"panelHeight"] doubleValue], [self.windowOptions[@"aiMaxHeight"] doubleValue]);
    [window layoutIfNeeded];
    self.resizing = NO;
}
- (void)displayText:(NSString *)text {
    self.textView.text = text;
    [self resizePanel];
}
- (void)close {
    dispatch_block_t callback = self.onClose; self.onClose = nil;
    [self.searchMenu dismiss]; self.searchMenu = nil;
    RSCloseWindowSurface(self.overlayWindow, self.panel); self.panel = nil;
    [self.previousWindow makeKeyWindow]; self.overlayWindow = nil;
    self.tokenView = nil; self.generating = NO;
    if (callback) callback();
}
- (NSString *)actionText {
    return self.tokenView ? self.tokenView.selectedText : self.result;
}
- (void)updateTokenActions {
    BOOL hasText = self.tokenView ? self.tokenView.hasSelection : self.result.length > 0;
    self.clipboardButton.enabled = hasText;
    self.replaceButton.enabled = hasText && self.completedResult;
}
- (void)leaveTokens {
    [self.tokenView removeFromSuperview];
    self.tokenView = nil;
    self.overlayWindow.windowLevel = RSKAPanelWindowLevel(self.windowOptions, @"aiWindowPriority");
    self.textView.hidden = NO;
    self.header.hidden = NO;
    self.backButton.hidden = YES;
    self.statusLabel.text = @"已完成";
    [self updateTokenActions];
    [self resizePanel];
}
- (void)tokenize:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || self.generating || !self.completedResult || self.tokenView) return;
    [self enterTokens];
}
- (void)enterTokens {
    if (self.generating || !self.completedResult || self.tokenView) return;
    NSArray *pieces = RSKATextPieces(self.result);
    if (!pieces.count) { self.statusLabel.text = @"文字超过 24,000 字，暂不支持分词；可复制全文。"; [self updateTokenActions]; return; }
    self.tokenView = [[RSKATokenView alloc] initWithPieces:pieces];
    self.overlayWindow.windowLevel = RSKAPanelWindowLevel(self.windowOptions, @"tokenWindowPriority");
    __weak RSKAPanel *weakSelf = self;
    self.tokenView.onSelectionChanged = ^{ [weakSelf updateTokenActions]; };
    self.tokenView.onLayoutChanged = ^{ [weakSelf resizePanel]; };
    self.tokenView.onGutterLongPress = ^{ [weakSelf leaveTokens]; };
    [self.contentStack insertArrangedSubview:self.tokenView atIndex:1];
    self.textView.hidden = YES;
    self.header.hidden = YES;
    [self updateTokenActions];
    [self resizePanel];
    RSKASelectionFeedback();
}
- (void)searchResult { NSString *text = [self actionText]; if (text.length) { [self close]; RSKAOpenSearch(text); } }
- (void)showSearchMenu:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan && [self actionText].length) {
        [self.searchMenu dismiss];
        RSKAAnchoredMenuView *menu = [RSKAAnchoredMenuView new];
        menu.menuWidth = 180; menu.centersTitles = YES; menu.presentsBelowSource = YES; menu.animatesDismissal = YES;
        NSString *text = [self actionText]; __weak RSKAPanel *weakSelf = self;
        for (NSDictionary *engine in RSKASearchEngines(RSKAConfig()))
            [menu addItemWithTitle:engine[@"name"] image:[UIImage systemImageNamed:@"magnifyingglass"] destructive:NO handler:^{ [weakSelf close]; RSKAOpenSearchEngine(engine, text); }];
        self.searchMenu = menu;
        [menu presentFromView:self.replaceButton inView:((RSKAPanelController *)self.overlayWindow.rootViewController).canvas];
    }
    [self.searchMenu trackGestureRecognizer:gesture];
}
- (void)copyResult {
    if ([self actionText].length) {
        [UIPasteboard.generalPasteboard setItems:@[@{UIPasteboardTypeAutomatic: [self actionText], @"com.moxuan.regionshot.input.internal": [NSData data]}]
                                        options:@{UIPasteboardOptionLocalOnly: @YES}];
        [self close];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"已复制");
    }
}
@end
static RSKAPanel *RSKASharedPanel(void) {
    static RSKAPanel *panel; static dispatch_once_t once;
    dispatch_once(&once, ^{ panel = [RSKAPanel new]; }); return panel;
}
BOOL RSKABeginAnswer(NSString *name, dispatch_block_t closed) {
    [NSNotificationCenter.defaultCenter postNotificationName:@"com.moxuan.regionshot.input.close" object:nil];
    RSKAPanel *panel = RSKASharedPanel(); [panel close];
    if (![panel show]) return NO;
    panel.onClose = closed; panel.generating = YES; panel.completedResult = NO;
    panel.statusLabel.text = [name stringByAppendingString:@" · 正在生成"];
    panel.result = @""; [panel displayText:@""]; [panel.spinner startAnimating];
    return YES;
}
void RSKAUpdateAnswer(NSString *text, BOOL finished, NSString *error) {
    RSKAPanel *panel = RSKASharedPanel(); if (!panel.panel) return;
    panel.result = text ?: @""; panel.generating = !finished;
    panel.completedResult = finished && panel.result.length > 0;
    [panel displayText:error.length ? [NSString stringWithFormat:@"%@\n\n%@", panel.result, error] : panel.result];
    if (finished) { [panel.spinner stopAnimating]; panel.statusLabel.text = error.length ? @"未完成" : @"已完成 · 长按文字分词"; }
    [panel updateTokenActions];
}
void RSKAOpenTokens(NSString *text) {
    [RSKASharedPanel() close];
    NSMutableDictionary *request = [@{@"text":text ?: @""} mutableCopy];
    [NSNotificationCenter.defaultCenter postNotificationName:@"com.moxuan.regionshot.input.tokens" object:request];
    if ([request[@"handled"] boolValue]) return;
    RSKAPanel *panel = RSKASharedPanel(); [panel close]; if (!text.length || ![panel show]) return;
    panel.result = text; panel.completedResult = YES; panel.generating = NO;
    [panel displayText:text]; [panel enterTokens];
}

void RSKAClosePanel(void) { [RSKASharedPanel() close]; [NSNotificationCenter.defaultCenter postNotificationName:@"com.moxuan.regionshot.input.close" object:nil]; }
