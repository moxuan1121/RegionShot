#define RS_PANEL_CONTROLLER RSInputPanelController
#import "../Geometry/RSPanelController.h"
// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import "RSInputInterface.h"
#import "RSInputCore.h"
#import "RSInputStream.h"
#import "RSInputStore.h"
#import "RSInputTokenView.h"
#import "RSInputClipboard.h"
#import "RSInputOptions.h"
#import "RSInputAnchoredMenuView.h"
#import "../Geometry/RSOrientation.h"

void RSInputSelectionFeedback(void) {
    static UISelectionFeedbackGenerator *feedback;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ feedback = [UISelectionFeedbackGenerator new]; });
    [feedback selectionChanged];
    [feedback prepare];
}

static UIWindow *RSInputWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (window.isKeyWindow) return window;
    }
    return nil;
}

static UIWindowLevel RSInputPanelWindowLevel(NSDictionary *options, NSString *key) {
    double priority = [options[key] doubleValue];
    return (UIWindowLevel)priority;
}

static __weak UIResponder *RSInputResponder;
@interface UIResponder (RSInputCapture)
- (void)rsinput_captureInput:(id)sender;
@end
@implementation UIResponder (RSInputCapture)
- (void)rsinput_captureInput:(__unused id)sender { RSInputResponder = self; }
@end

static UIResponder<UITextInput> *RSInputInput(void) {
    RSInputResponder = nil;
    [UIApplication.sharedApplication sendAction:@selector(rsinput_captureInput:) to:nil from:nil forEvent:nil];
    UIResponder *target = RSInputResponder;
    for (NSString *name in @[@"beginningOfDocument", @"endOfDocument", @"selectedTextRange",
            @"markedTextRange", @"textInRange:", @"textRangeFromPosition:toPosition:",
            @"positionFromPosition:offset:", @"offsetFromPosition:toPosition:", @"replaceRange:withText:"])
        if (![target respondsToSelector:NSSelectorFromString(name)]) return nil;
    return (id)target;
}

static BOOL RSInputIsSecure(id<UITextInput> target) {
    return [target respondsToSelector:@selector(isSecureTextEntry)] && target.secureTextEntry;
}

static NSString *RSInputFullText(id<UITextInput> target) {
    UITextPosition *start = target.beginningOfDocument, *end = target.endOfDocument;
    if (!start || !end) return nil;
    UITextRange *range = [target textRangeFromPosition:start toPosition:end];
    return range ? [target textInRange:range] : nil;
}

@interface RSInputCard : UIView
@end
@implementation RSInputCard
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.layer.cornerRadius].CGPath;
}
@end

@interface RSInputPanelWindow : UIWindow
@end
@implementation RSInputPanelWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view || hit == ((RSInputPanelController *)self.rootViewController).canvas ? nil : hit;
}
@end

@interface RSInputPanel : NSObject <NSURLSessionDataDelegate>
@property(strong) UIView *panel;
@property(strong) UIWindow *overlayWindow;
@property(weak) UIWindow *previousWindow;
@property(copy) void (^searchAction)(NSString *);
@property(strong) UITextView *textView;
@property(strong) UIStackView *contentStack;
@property(strong) UIStackView *header;
@property(strong) RSInputTokenView *tokenView;
@property(strong) UIButton *backButton;
@property(strong) UIButton *replaceButton;
@property(strong) UIButton *clipboardButton;
@property(strong) RSInputAnchoredMenuView *searchMenu;
@property(weak) UIResponder<UITextInput> *target;
@property(copy) NSString *original;
@property(copy) NSString *result;
@property NSRange range;
@property BOOL inputInvalidated;
@property(strong) NSURLSession *session;
@property(strong) NSURLSessionDataTask *task;
@property(strong) RSInputStream *stream;
@property(strong) NSMutableData *responseData;
@property BOOL streaming;
@property BOOL generating;
@property BOOL completedResult;
@property(strong) UILabel *statusLabel;
@property(strong) UIActivityIndicatorView *spinner;
@property(strong) NSLayoutConstraint *heightConstraint;
@property(strong) NSTimer *timer;
@property NSTimeInterval startedAt;
@property NSTimeInterval lastPaint;
@property(strong) NSDictionary *windowOptions;
@property BOOL resizing;
- (void)displayText:(NSString *)text;
- (void)finishWithResult:(NSString *)result error:(NSString *)error;
- (void)run:(NSDictionary *)action copiedText:(NSString *)copied search:(void (^)(NSString *))search;
- (void)close;
- (void)enterTokens;
- (void)openCopiedText:(NSString *)text;
@end

@implementation RSInputPanel
- (instancetype)init {
    if ((self = [super init])) {
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(close) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(close) name:UIApplicationProtectedDataWillBecomeUnavailable object:nil];
        [center addObserver:self selector:@selector(invalidateInput:) name:UIKeyboardWillHideNotification object:nil];
        [center addObserver:self selector:@selector(invalidateInput:) name:UITextViewTextDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(invalidateInput:) name:UITextFieldTextDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(resizePanel) name:UIKeyboardDidChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(rotated:) name:@"com.moxuan.regionshot.orientation.target" object:nil];
        [center addObserver:self selector:@selector(rotated:) name:UIDeviceOrientationDidChangeNotification object:nil];
    }
    return self;
}
- (void)rotated:(NSNotification *)note {
    if (!self.overlayWindow) return;
    [self.searchMenu dismiss];
    NSNumber *target = note.userInfo[@"orientation"];
    ((RSInputPanelController *)self.overlayWindow.rootViewController).orientation = target ? target.integerValue : RSActiveOrientation(self.overlayWindow.windowScene);
    [self.overlayWindow.rootViewController.view setNeedsLayout];
    [self resizePanel];
}
- (void)invalidateInput:(NSNotification *)note {
    if ([note.name isEqualToString:UIKeyboardWillHideNotification] || note.object == self.target)
        self.inputInvalidated = YES;
    if (self.inputInvalidated && !self.searchAction) self.replaceButton.enabled = NO;
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
    self.windowOptions = RSInputPromptOptions(RSInputConfig());
    UIWindow *window = RSInputWindow();
    if (!window) return NO;
    self.previousWindow = window;
    self.overlayWindow = window.windowScene ? [[RSInputPanelWindow alloc] initWithWindowScene:window.windowScene] : [[RSInputPanelWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.overlayWindow.frame = UIScreen.mainScreen.fixedCoordinateSpace.bounds;
    RSInputPanelController *controller = [RSInputPanelController new];
    self.overlayWindow.rootViewController = controller;
    controller.view.backgroundColor = UIColor.clearColor;
    __weak typeof(self) weakSelf = self;
    controller.onLayout = ^{ [weakSelf resizePanel]; };
    self.overlayWindow.windowLevel = RSInputPanelWindowLevel(self.windowOptions, @"aiWindowPriority");
    if (self.searchAction) [self.overlayWindow makeKeyAndVisible];
    else self.overlayWindow.hidden = NO; // Keep the text input first responder for safe replacement.
    window = self.overlayWindow;
    UIView *panel = [RSInputCard new];
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
    self.replaceButton = [self button:self.searchAction ? @"搜索" : @"替换" action:self.searchAction ? @selector(searchResult) : @selector(replace)];
    if (self.searchAction) {
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
    controller.orientation = RSActiveOrientation(window.windowScene);
    RSApplyWindowOrientation(window, UIInterfaceOrientationPortrait);
    [controller.view setNeedsLayout]; [controller.view layoutIfNeeded];
    UIView *host = controller.canvas;
    [host addSubview:panel];
    self.heightConstraint = [panel.heightAnchor constraintEqualToConstant:160];
    self.heightConstraint.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor constant:12],
        [panel.trailingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [panel.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:8],
        self.heightConstraint,
        [panel.bottomAnchor constraintLessThanOrEqualToAnchor:host.keyboardLayoutGuide.topAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-10]
    ]];
    self.replaceButton.enabled = NO;
    self.clipboardButton.enabled = NO;
    return YES;
}
- (void)resizePanel {
    UIWindow *window = self.panel.window;
    if (!window || self.resizing) return;
    self.resizing = YES;
    [window layoutIfNeeded];
    CGFloat width = MAX(1, self.contentStack.bounds.size.width);
    CGFloat contentHeight;
    if (self.tokenView) {
        [self.tokenView layoutIfNeeded];
        contentHeight = self.tokenView.collectionViewLayout.collectionViewContentSize.height;
    } else contentHeight = [self.textView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height;
    CGFloat chrome = 20 + self.contentStack.spacing * 2;
    for (UIView *view in self.contentStack.arrangedSubviews) {
        if (view.hidden || view == self.textView || view == self.tokenView) continue;
        chrome += [view systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
            withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    }
    UIView *host = ((RSInputPanelController *)window.rootViewController).canvas;
    CGFloat available = MAX(0, host.bounds.size.height - host.safeAreaInsets.top - host.safeAreaInsets.bottom - 20);
    CGFloat percent = [self.windowOptions[self.tokenView ? @"tokenMaxHeight" : @"aiMaxHeight"] doubleValue];
    self.heightConstraint.constant = RSInputFittedPanelHeight(contentHeight, chrome, available, percent);
    [window layoutIfNeeded];
    self.resizing = NO;
}
- (void)displayText:(NSString *)text {
    self.textView.text = text;
    [self resizePanel];
}
- (void)updateProgress {
    self.statusLabel.text = [NSString stringWithFormat:@"%@ · %.0f 秒", self.stream.text.length ? @"正在生成" : @"等待首字", NSDate.timeIntervalSinceReferenceDate - self.startedAt];
    [self resizePanel];
}
- (void)close {
    [self.session invalidateAndCancel];
    self.session = nil;
    self.task = nil;
    self.stream = nil;
    self.responseData = nil;
    self.generating = NO;
    self.completedResult = NO;
    [self.timer invalidate];
    self.timer = nil;
    [self.panel removeFromSuperview];
    self.panel = nil;
    self.target = nil;
    self.original = nil;
    self.result = nil;
    self.textView = nil;
    self.replaceButton = nil;
    self.clipboardButton = nil;
    [self.searchMenu dismiss];
    self.searchMenu = nil;
    self.statusLabel = nil;
    self.spinner = nil;
    self.heightConstraint = nil;
    self.contentStack = nil;
    self.header = nil;
    self.tokenView = nil;
    self.backButton = nil;
    if (self.overlayWindow) {
        self.overlayWindow.hidden = YES;
        [self.previousWindow makeKeyWindow];
        self.overlayWindow = nil;
        self.previousWindow = nil;
    }
    self.searchAction = nil;
}
- (void)run:(NSDictionary *)action copiedText:(NSString *)copied search:(void (^)(NSString *))search {
    [self close];
    self.searchAction = search;
    if (![self show]) return;
    self.inputInvalidated = NO;
    if (!copied) {
    self.target = RSInputInput();
    if (!self.target || RSInputIsSecure(self.target)) {
        [self displayText:@"此输入框不支持 AI 处理，或属于密码输入框。"];
        return;
    }
    if (self.target.markedTextRange) {
        [self displayText:@"请先选择拼音候选词，完成输入后再调用 AI。"];
        return;
    }
    self.original = RSInputFullText(self.target);
    if (!self.original.length || self.original.length > 12000) {
        [self displayText:@"请先输入文字。支持最多 12,000 个 UTF-16 单元的输入框内容。"];
        return;
    }
    UITextRange *selection = self.target.selectedTextRange;
    if (!selection) { [self displayText:@"无法确定输入范围，原文未修改。"]; return; }
    NSInteger start = [self.target offsetFromPosition:self.target.beginningOfDocument toPosition:selection.start];
    NSInteger length = [self.target offsetFromPosition:selection.start toPosition:selection.end];
    if (start < 0 || length < 0 || (NSUInteger)start > self.original.length ||
        (NSUInteger)length > self.original.length - (NSUInteger)start) {
        [self displayText:@"输入范围无效，原文未修改。"]; return;
    }
    self.range = length ? NSMakeRange(start, length) : NSMakeRange(0, self.original.length);
    } else {
        if (![copied isKindOfClass:NSString.class] || !copied.length || copied.length > 12000) {
            [self displayText:@"待处理文字为空或超过 12,000 个字符。"]; return;
        }
        self.original = copied;
        self.range = NSMakeRange(0, copied.length);
    }
    NSDictionary *config = RSInputConfig();
    NSString *key = [config[@"key"] isKindOfClass:NSString.class] ? config[@"key"] : nil;
    NSString *failure = RSInputConfigError(config[@"endpoint"], config[@"model"], key);
    if (failure) { [self displayText:[failure stringByAppendingString:@"\n请打开系统设置 → RegionShot。"]]; return; }
    if (!RSInputValidActions(@[action])) { [self displayText:@"功能配置无效。"]; return; }
    NSString *input = [self.original substringWithRange:self.range];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:config[@"endpoint"]]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 45;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    request.HTTPBody = RSInputRequestBody(config[@"model"], action[@"prompt"], input);
    BOOL fast = !config[@"fastResponse"] || [config[@"fastResponse"] boolValue];
    if (fast && RSInputSupportsFastResponse(config[@"endpoint"], config[@"model"])) {
        NSMutableDictionary *body = [[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL] mutableCopy];
        body[@"enable_thinking"] = @NO;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    }
    [request setValue:@"text/event-stream, application/json" forHTTPHeaderField:@"Accept"];
    if (!request.HTTPBody) { [self displayText:@"无法创建请求，原文未修改。"]; return; }
    [self displayText:[NSString stringWithFormat:@"%@ · 正在处理…\n关闭可取消。", action[@"title"]]];
    NSURLSessionConfiguration *sessionConfig = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    sessionConfig.timeoutIntervalForResource = 45;
    sessionConfig.URLCache = nil;
    sessionConfig.HTTPCookieStorage = nil;
    sessionConfig.URLCredentialStorage = nil;
    sessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    self.session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:NSOperationQueue.mainQueue];
    self.stream = [RSInputStream new];
    self.responseData = [NSMutableData data];
    self.streaming = NO;
    self.generating = YES;
    self.startedAt = NSDate.timeIntervalSinceReferenceDate;
    self.lastPaint = 0;
    [self.spinner startAnimating];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
    [self updateProgress];
    self.task = [self.session dataTaskWithRequest:request];
    [self.task resume];
}
- (void)finishWithResult:(NSString *)result error:(NSString *)error {
    self.generating = NO;
    [self.timer invalidate];
    self.timer = nil;
    [self.spinner stopAnimating];
    [self.session invalidateAndCancel];
    self.session = nil;
    self.task = nil;
    self.result = result;
    BOOL complete = !error && RSInputTrim(result).length > 0;
    self.completedResult = complete;
    self.statusLabel.text = complete ? @"已完成" : @"未完成 · 原文未修改";
    [self displayText:error ? [NSString stringWithFormat:@"%@%@", error, result.length ? [@"\n\n已接收的部分内容：\n" stringByAppendingString:result] : @""] : result];
    self.clipboardButton.enabled = result.length > 0;
    self.replaceButton.enabled = complete && (self.searchAction || !self.inputInvalidated);
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, complete ? @"AI 结果已就绪" : @"AI 请求未完成");
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (session != self.session || task != self.task) { completionHandler(NSURLSessionResponseCancel); return; }
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (status < 200 || status >= 300) {
        completionHandler(NSURLSessionResponseCancel);
        NSString *error = nil;
        RSInputParseResponse(nil, status, &error);
        [self finishWithResult:nil error:error];
        return;
    }
    if (response.expectedContentLength > 1024 * 1024) {
        completionHandler(NSURLSessionResponseCancel);
        [self finishWithResult:nil error:@"响应超过 1 MB，已停止接收。"]; return;
    }
    self.streaming = [response.MIMEType.lowercaseString isEqualToString:@"text/event-stream"];
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (session != self.session || task != self.task || !self.panel) return;
    if (self.streaming) {
        [self.stream appendData:data];
        if (self.stream.error || self.stream.finished) {
            NSString *error = self.stream.error;
            if (!error && !RSInputTrim(self.stream.text).length) error = @"没有收到可用文字。";
            [self finishWithResult:self.stream.text error:error];
        } else if (self.stream.text.length && NSDate.timeIntervalSinceReferenceDate - self.lastPaint >= 0.08) {
            self.lastPaint = NSDate.timeIntervalSinceReferenceDate;
            [self displayText:self.stream.text];
        }
    } else {
        if (data.length > 1024 * 1024 - self.responseData.length) {
            [self finishWithResult:nil error:@"响应超过 1 MB，已停止接收。"]; return;
        }
        [self.responseData appendData:data];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (session != self.session || task != self.task || !self.panel) return;
    if (error) {
        [self finishWithResult:self.streaming ? self.stream.text : nil error:error.code == NSURLErrorTimedOut ? @"请求超时，请重试或换用更快的模型。" : @"网络连接中断，请检查连接后重试。"];
        return;
    }
    NSString *failure = nil, *result = nil;
    if (self.streaming) {
        [self.stream endOfInput];
        result = self.stream.text;
        failure = self.stream.error;
        if (!failure && !RSInputTrim(result).length) failure = @"没有收到可用文字。";
    } else result = RSInputParseResponse(self.responseData, 200, &failure);
    [self finishWithResult:result error:failure];
}
- (void)URLSession:(__unused NSURLSession *)session task:(__unused NSURLSessionTask *)task
        willPerformHTTPRedirection:(__unused NSHTTPURLResponse *)response
        newRequest:(__unused NSURLRequest *)request
        completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil); // Never forward the API credential or input to a redirect destination.
}
- (NSString *)actionText {
    return self.tokenView ? self.tokenView.selectedText : self.result;
}
- (void)updateTokenActions {
    BOOL hasText = self.tokenView ? self.tokenView.hasSelection : self.result.length > 0;
    self.clipboardButton.enabled = hasText;
    self.replaceButton.enabled = hasText && self.completedResult && (self.searchAction || !self.inputInvalidated);
}
- (void)leaveTokens {
    [self.tokenView removeFromSuperview];
    self.tokenView = nil;
    self.overlayWindow.windowLevel = RSInputPanelWindowLevel(self.windowOptions, @"aiWindowPriority");
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
- (void)openCopiedText:(NSString *)text {
    [self close];
    if (![text isKindOfClass:NSString.class] || !text.length || text.length > 24000) return;
    self.searchAction = ^(NSString *selected) { RSInputOpenSearch(selected); };
    if (![self show]) return;
    self.result = text;
    self.completedResult = YES;
    self.textView.accessibilityLabel = @"复制的文字";
    [self displayText:text];
    [self enterTokens];
}
- (void)enterTokens {
    if (self.generating || !self.completedResult || self.tokenView) return;
    NSArray *pieces = RSInputTextPieces(self.result);
    if (!pieces.count) return;
    self.tokenView = [[RSInputTokenView alloc] initWithPieces:pieces];
    self.overlayWindow.windowLevel = RSInputPanelWindowLevel(self.windowOptions, @"tokenWindowPriority");
    __weak RSInputPanel *weakSelf = self;
    self.tokenView.onSelectionChanged = ^{ [weakSelf updateTokenActions]; };
    self.tokenView.onLayoutChanged = ^{ [weakSelf resizePanel]; };
    self.tokenView.onGutterLongPress = ^{ [weakSelf leaveTokens]; };
    [self.contentStack insertArrangedSubview:self.tokenView atIndex:2];
    self.textView.hidden = YES;
    self.header.hidden = YES;
    [self updateTokenActions];
    [self resizePanel];
    RSInputSelectionFeedback();
}
- (void)searchResult {
    if (self.generating || !self.replaceButton.enabled || !self.result.length || !self.searchAction) return;
    void (^search)(NSString *) = self.searchAction;
    NSString *text = [self actionText];
    [self close];
    search(text);
}
- (void)showSearchMenu:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (!self.tokenView || !self.searchAction || !self.replaceButton.enabled || ![self actionText].length) return;
        [self.searchMenu dismiss];
        RSInputAnchoredMenuView *menu = [RSInputAnchoredMenuView new];
        menu.menuWidth = 180;
        menu.centersTitles = YES;
        menu.presentsBelowSource = YES;
        menu.animatesDismissal = YES;
        NSString *text = [[self actionText] copy];
        __weak RSInputPanel *weakSelf = self;
        for (NSDictionary *engine in RSInputSearchEngines(RSInputConfig())) {
            [menu addItemWithTitle:engine[@"name"] image:[UIImage systemImageNamed:@"magnifyingglass"]
                destructive:NO handler:^{
                    [weakSelf close];
                    RSInputOpenSearchEngine(engine, text);
                }];
        }
        for (NSDictionary *action in RSInputActions()) {
            [menu addItemWithTitle:action[@"title"] image:[UIImage systemImageNamed:@"sparkles"]
                destructive:NO handler:^{
                    [weakSelf close];
                    RSInputRunCopiedAction(action, text, ^(NSString *result) { RSInputOpenSearch(result); });
                }];
        }
        menu.onDismiss = ^{ weakSelf.searchMenu = nil; };
        self.searchMenu = menu;
        // The panel itself is attached directly to the overlay window. Attach
        // the menu there afterwards so it stays above every panel priority.
        [menu presentFromView:self.replaceButton inView:((RSInputPanelController *)self.overlayWindow.rootViewController).canvas];
        RSInputSelectionFeedback();
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
- (void)replace {
    UIResponder<UITextInput> *target = self.target;
    NSString *current = target && !RSInputIsSecure(target) ? RSInputFullText(target) : nil;
    if (self.generating || !self.replaceButton.enabled || !target || RSInputInput() != target || !target.isFirstResponder || self.inputInvalidated ||
        RSInputIsSecure(target) || target.markedTextRange ||
        !RSInputCanReplace(self.original, current, self.range, [self actionText])) {
        self.replaceButton.enabled = NO;
        [self displayText:[@"输入框或内容已变化，请复制结果或重新调用 AI。\n\n" stringByAppendingString:self.result ?: @""]];
        return;
    }
    UITextPosition *start = [target positionFromPosition:target.beginningOfDocument offset:self.range.location];
    UITextPosition *end = [target positionFromPosition:start offset:self.range.length];
    UITextRange *range = start && end ? [target textRangeFromPosition:start toPosition:end] : nil;
    if (!range) { self.replaceButton.enabled = NO; return; }
    NSString *expected = [current stringByReplacingCharactersInRange:self.range withString:[self actionText]];
    [target replaceRange:range withText:[self actionText]];
    if ([RSInputFullText(target) isEqualToString:expected]) [self close];
    else {
        self.replaceButton.enabled = NO;
        [self displayText:[@"输入框未确认替换结果，请检查输入框；仍可复制下方结果。\n\n" stringByAppendingString:self.result]];
    }
}
@end

static RSInputPanel *RSInputSharedPanel(void) {
    static RSInputPanel *panel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ panel = [RSInputPanel new]; });
    return panel;
}

void RSInputOpenCopiedText(NSString *text) { [RSInputSharedPanel() openCopiedText:text]; }
BOOL RSInputIsPanelVisible(void) { return RSInputSharedPanel().panel != nil; }
void RSInputFinishExternalWindowHandoff(UIWindow *closedWindow) {
    RSInputPanel *panel = RSInputSharedPanel();
    if (!panel.panel) return;
    UIWindow *current = RSInputWindow();
    if (current && current != closedWindow && current != panel.overlayWindow) panel.previousWindow = current;
    else if (panel.previousWindow == closedWindow) panel.previousWindow = nil;
    [panel.overlayWindow makeKeyAndVisible];
    [panel resizePanel];
    [panel.overlayWindow layoutIfNeeded];
}
void RSInputClosePanel(void) { [RSInputSharedPanel() close]; }

void RSInputRunAction(NSDictionary *action) { [RSInputSharedPanel() run:action copiedText:nil search:nil]; }


void RSInputRunCopiedAction(NSDictionary *action, NSString *text, void (^search)(NSString *)) { [RSInputSharedPanel() run:action copiedText:text search:search]; }
