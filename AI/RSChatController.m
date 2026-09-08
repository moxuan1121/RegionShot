#import "RSChatController.h"
#import "RSSSEDecoder.h"
#import "../Preferences/RSOptions.h"
#import <Security/Security.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RSChatWindow : UIWindow
@property (nonatomic, weak) UIView *activeSurface;
@end
@implementation RSChatWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.activeSurface && !CGRectContainsPoint(self.activeSurface.frame, point)) return nil;
    return [super hitTest:point withEvent:event];
}
@end

@interface RSChatController () <NSURLSessionDataDelegate, PHPickerViewControllerDelegate,
    UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextViewDelegate>
@property (nonatomic, strong) RSChatWindow *host;
@property (nonatomic, weak) UIWindow *previousKey;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIStackView *chat;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UIImageView *chip;
@property (nonatomic, strong) UIView *chipContainer;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *modelButton;
@property (nonatomic, strong) UIButton *ball;
@property (nonatomic, strong) UIImage *attachment;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *history;
@property (nonatomic, strong) NSMutableArray<UIView *> *rows;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) RSSSEDecoder *decoder;
@property (nonatomic, strong) NSMutableData *body;
@property (nonatomic, strong) NSMutableString *answer;
@property (nonatomic, strong) UITextView *reply;
@property (nonatomic, copy) NSString *failure;
@property (nonatomic) NSInteger responseStatus;
@property (nonatomic) BOOL streaming;
@property (nonatomic) BOOL done;
@property (nonatomic) BOOL stopped;
@property (nonatomic) NSUInteger received;
@property (nonatomic) BOOL refreshScheduled;
@end

static RSChatController *RSActiveChat;
static NSUserDefaults *RSChatPreferences(void) {
    static NSUserDefaults *prefs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"]; });
    return prefs;
}
static NSMutableDictionary *RSKeyQuery(void) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:@"com.moxuan.regionshot.ai",
              (__bridge id)kSecAttrAccount:@"api-key"} mutableCopy];
}
static NSString *RSReadKey(void) {
    NSMutableDictionary *query = RSKeyQuery();
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSData *data = CFBridgingRelease(result);
    return status == errSecSuccess ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}
static OSStatus RSWriteKey(NSString *key) {
    NSMutableDictionary *query = RSKeyQuery();
    NSDictionary *value = @{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)value);
    if (status != errSecItemNotFound) return status;
    [query addEntriesFromDictionary:value];
    return SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}

@implementation RSChatController
+ (void)showImage:(UIImage *)image scene:(UIWindowScene *)scene {
    NSAssert(NSThread.isMainThread, @"Chat UI requires main thread");
    if (RSActiveChat) {
        [RSActiveChat restore];
        RSActiveChat.attachment = image;
        RSActiveChat.chip.image = image;
        RSActiveChat.chip.hidden = image == nil;
        RSActiveChat.chipContainer.hidden = image == nil;
        if (image && [RSOption(@"AIAutoImage") boolValue] && !RSActiveChat.task) [RSActiveChat send];
        return;
    }
    RSChatController *controller = [self new];
    controller.attachment = image;
    controller.history = [NSMutableArray array];
    controller.rows = [NSMutableArray array];
    for (UIWindow *window in scene.windows) if (window.isKeyWindow) controller.previousKey = window;
    RSChatWindow *window = scene ? [[RSChatWindow alloc] initWithWindowScene:scene]
                                : [[RSChatWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    window.windowLevel = UIWindowLevelAlert + 150;
    window.backgroundColor = UIColor.clearColor;
    controller.host = window;
    window.rootViewController = controller;
    RSActiveChat = controller;
    [window makeKeyAndVisible];
    [controller loadViewIfNeeded];
    if (image && [RSOption(@"AIAutoImage") boolValue]) [controller send];
}
+ (void)showText:(NSString *)text scene:(UIWindowScene *)scene sendImmediately:(BOOL)send {
    [self showImage:nil scene:scene];
    RSActiveChat.input.text = text;
    [RSActiveChat updatePlaceholder];
    if (send && !RSActiveChat.task) [RSActiveChat send];
}
+ (void)showServiceSettings {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
        if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)candidate; break; }
    [self showImage:nil scene:scene];
    [RSActiveChat settings];
}
- (UIButton *)button:(NSString *)symbol title:(NSString *)title action:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.accessibilityLabel = title;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:44].active = YES;
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.36];
    self.card = [UIView new];
    self.card.backgroundColor = UIColor.systemBackgroundColor;
    self.card.layer.cornerRadius = 30;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.clipsToBounds = YES;
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.card];
    UIStackView *content = [UIStackView new];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 12;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:content];
    UILabel *title = [UILabel new];
    title.text = @"图片问答";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.modelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.modelButton.titleLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    self.modelButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.modelButton setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    self.modelButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self.modelButton addTarget:self action:@selector(settings) forControlEvents:UIControlEventTouchUpInside];
    [self updateModelTitle];
    UIButton *keyboard = [self button:@"keyboard" title:@"收起键盘" action:@selector(hideKeyboard)];
    UIButton *minimize = [self button:@"minus" title:@"最小化" action:@selector(minimize)];
    UIButton *close = [self button:@"xmark" title:@"关闭对话" action:@selector(close)];
    for (UIButton *button in @[keyboard, minimize, close]) {
        button.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.10];
        button.layer.cornerRadius = 22;
        [button setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium] forImageInState:UIControlStateNormal];
    }
    UIView *spacer = [UIView new];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.modelButton, spacer, keyboard, minimize, close]];
    top.alignment = UIStackViewAlignmentCenter;
    top.spacing = 6;
    [content addArrangedSubview:top];
    self.chip = [[UIImageView alloc] initWithImage:self.attachment];
    self.chip.hidden = self.attachment == nil;
    self.chip.contentMode = UIViewContentModeScaleAspectFill;
    self.chip.clipsToBounds = YES;
    self.chip.layer.cornerRadius = 14;
    self.chip.layer.cornerCurve = kCACornerCurveContinuous;
    self.chip.layer.borderWidth = 7;
    self.chip.layer.borderColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.10].CGColor;
    self.chip.userInteractionEnabled = YES;
    self.chip.accessibilityLabel = @"发送给 AI 的图片，轻按移除";
    self.chip.accessibilityTraits = UIAccessibilityTraitButton;
    [self.chip addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearAttachment)]];
    self.chipContainer = [UIView new];
    self.chipContainer.hidden = self.attachment == nil;
    [self.chipContainer addSubview:self.chip];
    self.chip.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.chipContainer.heightAnchor constraintEqualToConstant:82],
        [self.chip.trailingAnchor constraintEqualToAnchor:self.chipContainer.trailingAnchor],
        [self.chip.topAnchor constraintEqualToAnchor:self.chipContainer.topAnchor],
        [self.chip.widthAnchor constraintEqualToConstant:76],
        [self.chip.heightAnchor constraintEqualToConstant:76]]];
    [content addArrangedSubview:self.chipContainer];
    self.scroll = [UIScrollView new];
    self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [content addArrangedSubview:self.scroll];
    self.chat = [UIStackView new];
    self.chat.axis = UILayoutConstraintAxisVertical;
    self.chat.spacing = 12;
    self.chat.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:self.chat];
    self.input = [UITextView new];
    self.input.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.input.delegate = self;
    self.input.textContainerInset = UIEdgeInsetsMake(13, 14, 8, 14);
    self.input.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.70];
    self.input.layer.cornerRadius = 24;
    self.input.layer.cornerCurve = kCACornerCurveContinuous;
    self.input.accessibilityLabel = @"输入问题";
    [self.input.heightAnchor constraintEqualToConstant:48].active = YES;
    self.placeholder = [UILabel new];
    self.placeholder.text = @"问点什么…";
    self.placeholder.textColor = UIColor.placeholderTextColor;
    self.placeholder.font = self.input.font;
    self.placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    [self.input addSubview:self.placeholder];
    [NSLayoutConstraint activateConstraints:@[
        [self.placeholder.leadingAnchor constraintEqualToAnchor:self.input.leadingAnchor constant:18],
        [self.placeholder.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor]]];
    UIButton *add = [self button:@"plus" title:@"添加图片" action:@selector(attachments)];
    add.backgroundColor = UIColor.systemBlueColor; add.tintColor = UIColor.whiteColor; add.layer.cornerRadius = 24;
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"发送" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.sendButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.sendButton.backgroundColor = UIColor.systemBlueColor;
    self.sendButton.layer.cornerRadius = 24;
    [self.sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    [self.sendButton.widthAnchor constraintEqualToConstant:88].active = YES;
    [self.sendButton.heightAnchor constraintEqualToConstant:48].active = YES;
    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[self.input, add, self.sendButton]];
    bottom.alignment = UIStackViewAlignmentCenter;
    bottom.spacing = 8;
    [content addArrangedSubview:bottom];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *height = [self.card.heightAnchor constraintEqualToAnchor:safe.heightAnchor multiplier:0.56];
    height.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *center = [self.card.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor];
    center.priority = UILayoutPriorityDefaultHigh - 1;
    [NSLayoutConstraint activateConstraints:@[
        [self.card.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.card.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.card.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:12],
        [self.card.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12],
        height, center,
        [content.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],
        [content.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:14],
        [content.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-14],
        [self.chat.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],
        [self.chat.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],
        [self.chat.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [self.chat.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
        [self.chat.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor]]];
    self.ball = [self button:@"text.bubble.fill" title:@"恢复图片问答" action:@selector(restore)];
    self.ball.frame = CGRectMake(16, 120, 44, 44);
    self.ball.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.ball.layer.cornerRadius = 26;
    self.ball.hidden = YES;
    [self.ball addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panBall:)]];
    [self.view addSubview:self.ball];
    [self applyAppearance];
}
- (void)applyAppearance {
    self.overrideUserInterfaceStyle = (UIUserInterfaceStyle)[RSOption(@"AITheme") integerValue];
    CGFloat size = [RSOption(@"AIBallSize") doubleValue];
    for (NSLayoutConstraint *constraint in self.ball.constraints)
        if (constraint.firstAttribute == NSLayoutAttributeWidth || constraint.firstAttribute == NSLayoutAttributeHeight) constraint.constant = size;
    self.ball.bounds = CGRectMake(0, 0, size, size); self.ball.layer.cornerRadius = size / 2;
    self.ball.alpha = [RSOption(@"AIBallOpacity") doubleValue];
}
- (void)updateModelTitle {
    NSString *model = [RSChatPreferences() stringForKey:@"AIModel"];
    [self.modelButton setTitle:model.length ? model : @"配置模型" forState:UIControlStateNormal];
}
- (void)hideKeyboard { [self.view endEditing:YES]; }
- (void)minimize {
    [self hideKeyboard];
    self.card.hidden = YES;
    self.ball.hidden = NO;
    self.view.backgroundColor = UIColor.clearColor;
    self.host.activeSurface = self.ball;
    [self.host resignKeyWindow];
    [self.previousKey makeKeyWindow];
}
- (void)restore {
    RSReloadOptions(); [self applyAppearance];
    self.host.activeSurface = nil;
    self.card.hidden = NO;
    self.ball.hidden = YES;
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.36];
    [self.host makeKeyAndVisible];
}
- (void)panBall:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:self.view];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat radius = self.ball.bounds.size.width / 2;
    CGFloat x = MIN(MAX(self.ball.center.x + delta.x, CGRectGetMinX(safe) + radius), CGRectGetMaxX(safe) - radius);
    CGFloat y = MIN(MAX(self.ball.center.y + delta.y, CGRectGetMinY(safe) + radius), CGRectGetMaxY(safe) - radius);
    if (pan.state == UIGestureRecognizerStateEnded)
        x = x < CGRectGetMidX(safe) ? CGRectGetMinX(safe) + radius : CGRectGetMaxX(safe) - radius;
    self.ball.center = CGPointMake(x, y);
    [pan setTranslation:CGPointZero inView:self.view];
}
- (void)close {
    [self.session invalidateAndCancel];
    self.task = nil;
    self.session = nil;
    [self hideKeyboard];
    self.host.hidden = YES;
    [self.previousKey makeKeyWindow];
    self.host.rootViewController = nil;
    self.host = nil;
    RSActiveChat = nil;
}
- (void)message:(NSString *)message {
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"RegionShot" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)settings {
    if (self.task) { [self message:@"请先停止当前回复再修改服务配置。"]; return; }
    NSUserDefaults *prefs = RSChatPreferences();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"图片问答服务"
        message:@"填写支持图片的 Chat Completions 服务完整地址、模型名称和 API Key。" preferredStyle:UIAlertControllerStyleAlert];
    NSArray *values = @[[prefs stringForKey:@"AIEndpoint"] ?: @"", [prefs stringForKey:@"AIModel"] ?: @"", RSReadKey() ?: @""];
    NSArray *hints = @[@"https://…/v1/chat/completions", @"模型名称", @"API Key（保存在钥匙串）"];
    for (NSUInteger i = 0; i < 3; i++) [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = values[i]; field.placeholder = hints[i]; field.secureTextEntry = i == 2;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *endpoint = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *model = [alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSURL *url = [NSURL URLWithString:endpoint];
        if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length || url.user || url.password || !model.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self message:@"请填写有效的 HTTPS 服务地址和模型名称。"]; }); return;
        }
        OSStatus status = RSWriteKey(alert.textFields[2].text ?: @"");
        if (status != errSecSuccess) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self message:[NSString stringWithFormat:@"钥匙串保存失败（%d），配置未更改。", (int)status]]; }); return;
        }
        [prefs setObject:endpoint forKey:@"AIEndpoint"];
        [prefs setObject:model forKey:@"AIModel"];
        [prefs synchronize];
        [self updateModelTitle];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (UITextView *)addRow:(NSString *)text image:(UIImage *)image assistant:(BOOL)assistant index:(NSUInteger)index {
    UIStackView *row = [UIStackView new]; row.axis = UILayoutConstraintAxisVertical; row.spacing = 2;
    row.alignment = assistant ? UIStackViewAlignmentLeading : UIStackViewAlignmentTrailing;
    if (image) {
        UIImageView *preview = [[UIImageView alloc] initWithImage:image];
        preview.contentMode = UIViewContentModeScaleAspectFit;
        [preview.heightAnchor constraintEqualToConstant:120].active = YES;
        [row addArrangedSubview:preview];
    }
    UITextView *view = [UITextView new];
    view.text = text; view.editable = NO; view.scrollEnabled = NO;
    view.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    view.adjustsFontForContentSizeCategory = YES;
    view.backgroundColor = assistant ? [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.88] : [UIColor.systemBlueColor colorWithAlphaComponent:0.10];
    view.layer.cornerRadius = 20;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.textContainerInset = assistant ? UIEdgeInsetsMake(14, 14, 48, 14) : UIEdgeInsetsMake(12, 14, 12, 14);
    [view.widthAnchor constraintEqualToAnchor:self.chat.widthAnchor multiplier:0.82].active = YES;
    [row addArrangedSubview:view];
    if (assistant) {
        UIButton *regen = [self button:@"arrow.clockwise" title:@"重新回答" action:@selector(regenerate:)];
        UIButton *tokenize = [self button:@"character.textbox" title:@"分词" action:@selector(tokenize:)];
        UIButton *copy = [self button:@"doc.on.doc" title:@"复制回答" action:@selector(copyReply:)];
        for (UIButton *button in @[regen, tokenize, copy]) button.tag = index;
        UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[regen, tokenize, copy]];
        actions.spacing = 0;
        actions.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:actions];
        [NSLayoutConstraint activateConstraints:@[
            [actions.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-8],
            [actions.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-2]]];
    }
    [self.chat addArrangedSubview:row]; [self.rows addObject:row];
    return view;
}
- (void)copyReply:(UIButton *)button {
    if (button.tag < (NSInteger)self.history.count)
        UIPasteboard.generalPasteboard.string = self.history[button.tag][@"content"];
}
- (void)tokenize:(UIButton *)button {
    if (button.tag >= (NSInteger)self.history.count) return;
    NSString *text = self.history[button.tag][@"content"];
    if (!text.length) return;
    NSMutableDictionary *request = [@{@"text":text, @"handled":@NO} mutableCopy];
    // A synchronous in-process bridge; KeyboardAI owns its segmentation implementation.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.moxuan.regionshot.tokenize" object:request];
    if ([request[@"handled"] boolValue]) [self minimize];
    else [self message:@"请安装支持 RegionShot 分词接入的 KeyboardAI。"];
}
- (void)regenerate:(UIButton *)button {
    if (self.task || button.tag <= 0 || button.tag >= (NSInteger)self.history.count) return;
    NSUInteger userIndex = (NSUInteger)button.tag - 1;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重新回答"
        message:@"将从这条提问重新生成，并移除它之后的对话。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重新生成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        while (self.history.count > userIndex + 1) {
            [self.history removeLastObject];
            UIView *row = self.rows.lastObject;
            [self.chat removeArrangedSubview:row]; [row removeFromSuperview]; [self.rows removeLastObject];
        }
        [self startRequest];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)send {
    if (self.task) { self.stopped = YES; [self.task cancel]; return; }
    if (![RSChatPreferences() stringForKey:@"AIEndpoint"].length) { [self settings]; return; }
    NSString *text = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length && !self.attachment) return;
    if (text.length > 24000) { [self message:@"单次问题最多 24,000 字符。"]; return; }
    BOOL implicitImagePrompt = !text.length && self.attachment;
    if (!text.length) text = [RSOption(@"AIImagePrompt") length] ? RSOption(@"AIImagePrompt") : @"请描述图片内容。";
    NSMutableArray *content = [NSMutableArray arrayWithObject:@{@"type":@"text", @"text":text}];
    if (self.attachment) {
        NSData *jpeg = UIImageJPEGRepresentation(self.attachment, 0.85);
        if (!jpeg || jpeg.length > 12 * 1024 * 1024) { [self message:@"图片过大或无法读取，请使用小于 12 MB 的图片。"]; return; }
        NSString *url = [@"data:image/jpeg;base64," stringByAppendingString:[jpeg base64EncodedStringWithOptions:0]];
        [content addObject:@{@"type":@"image_url", @"image_url":@{@"url":url}}];
    }
    UIImage *sentImage = self.attachment;
    [self addRow:text image:nil assistant:NO index:self.history.count];
    if (implicitImagePrompt) self.rows.lastObject.hidden = YES;
    [self.history addObject:[@{@"role":@"user", @"content":content} mutableCopy]];
    self.input.text = @""; self.attachment = nil;
    self.chip.image = sentImage ?: self.chip.image;
    self.chip.hidden = self.chip.image == nil;
    self.chipContainer.hidden = self.chip.hidden;
    [self updatePlaceholder]; [self hideKeyboard];
    [self startRequest];
}
- (void)startRequest {
    NSUserDefaults *prefs = RSChatPreferences();
    NSURL *endpoint = [NSURL URLWithString:[prefs stringForKey:@"AIEndpoint"] ?: @""];
    if (![endpoint.scheme.lowercaseString isEqual:@"https"] || !endpoint.host.length || endpoint.user || endpoint.password || ![prefs stringForKey:@"AIModel"].length) {
        [self message:@"请先配置有效的 HTTPS 服务地址和模型。"]; return;
    }
    NSMutableArray *messages = self.history.mutableCopy;
    NSString *persona = RSOption(@"AIPersona");
    if (persona.length) [messages insertObject:@{@"role":@"system", @"content":persona} atIndex:0];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"model":[prefs stringForKey:@"AIModel"] ?: @"",
        @"messages":messages, @"stream":RSOption(@"AIStream")} options:0 error:&error];
    if (!data || data.length > 32 * 1024 * 1024) {
        [self message:error.localizedDescription ?: @"对话图片总量超过 32 MB，请关闭后开始新对话。"]; return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    request.HTTPMethod = @"POST"; request.HTTPBody = data; request.timeoutInterval = 120;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream, application/json" forHTTPHeaderField:@"Accept"];
    NSString *key = RSReadKey();
    if (key.length) [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    self.reply = [self addRow:@"正在思考…" image:nil assistant:YES index:self.history.count];
    [self.history addObject:[@{@"role":@"assistant", @"content":@""} mutableCopy]];
    self.answer = [NSMutableString string]; self.body = [NSMutableData data];
    self.done = NO; self.stopped = NO; self.received = 0; self.failure = nil;
    self.responseStatus = 0; self.streaming = NO;
    self.decoder = [RSSSEDecoder new];
    __weak typeof(self) weakSelf = self;
    self.decoder.onEvent = ^(NSString *event) { [weakSelf consumeEvent:event]; };
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForResource = 300;
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    self.task = [self.session dataTaskWithRequest:request];
    [self.sendButton setTitle:@"停止" forState:UIControlStateNormal];
    self.sendButton.accessibilityLabel = @"停止生成";
    [self.task resume];
}
- (void)consumeEvent:(NSString *)event {
    if (self.done || self.failure) return;
    if ([event isEqualToString:@"[DONE]"]) { self.done = YES; [self.task cancel]; return; }
    id json = [NSJSONSerialization JSONObjectWithData:[event dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) { self.failure = @"服务返回了无效的流式 JSON"; return; }
    if (json[@"error"]) { self.failure = @"服务拒绝了请求，请检查模型、密钥及额度。"; return; }
    id choices = json[@"choices"];
    if (![choices isKindOfClass:NSArray.class] || ![choices count]) return;
    id choice = choices[0];
    if (![choice isKindOfClass:NSDictionary.class]) return;
    id delta = choice[@"delta"];
    id piece = [delta isKindOfClass:NSDictionary.class] ? delta[@"content"] : nil;
    if ([piece isKindOfClass:NSString.class]) {
        if (self.answer.length + [piece length] > 256000) {
            self.failure = @"回答超过 256,000 字符，已停止接收。"; return;
        }
        [self.answer appendString:piece];
        if (!self.refreshScheduled) {
            self.refreshScheduled = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                weakSelf.refreshScheduled = NO;
                if (weakSelf.task) [weakSelf updateReply];
            });
        }
    }
}
- (void)updateReply {
    BOOL atBottom = self.scroll.contentOffset.y + self.scroll.bounds.size.height >= self.scroll.contentSize.height - 60;
    self.reply.text = self.answer;
    self.history.lastObject[@"content"] = self.answer.copy;
    if (atBottom && !self.card.hidden) {
        [self.chat layoutIfNeeded];
        [self.scroll layoutIfNeeded];
        [self.scroll setContentOffset:CGPointMake(0, MAX(0, self.scroll.contentSize.height - self.scroll.bounds.size.height)) animated:NO];
    }
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (task != self.task) { completionHandler(NSURLSessionResponseCancel); return; }
    self.responseStatus = [(NSHTTPURLResponse *)response statusCode];
    self.streaming = [response.MIMEType.lowercaseString isEqualToString:@"text/event-stream"];
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // The configured endpoint must be final; credentials never follow a redirected host.
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (task != self.task || self.done) return;
    self.received += data.length;
    if (self.received > 8 * 1024 * 1024) { self.failure = @"响应超过 8 MB，已停止接收。"; [task cancel]; return; }
    if (self.streaming && self.responseStatus >= 200 && self.responseStatus < 300) {
        [self.decoder appendData:data];
        if (self.decoder.error) self.failure = self.decoder.error.localizedDescription;
        if (self.failure) [task cancel];
    } else [self.body appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (task != self.task) return;
    if (!self.responseStatus && error) self.failure = error.localizedDescription;
    else if (self.responseStatus < 200 || self.responseStatus >= 300)
        self.failure = [NSString stringWithFormat:@"请求失败（HTTP %ld）。请检查服务地址、模型及密钥。", (long)self.responseStatus];
    else if (!self.streaming && !error) {
        id json = [NSJSONSerialization JSONObjectWithData:self.body options:0 error:nil];
        id choices = [json isKindOfClass:NSDictionary.class] ? json[@"choices"] : nil;
        id choice = [choices isKindOfClass:NSArray.class] && [choices count] ? choices[0] : nil;
        id message = [choice isKindOfClass:NSDictionary.class] ? choice[@"message"] : nil;
        id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
        if ([content isKindOfClass:NSString.class]) { [self.answer setString:content]; self.done = YES; }
        else self.failure = @"服务未返回有效的文字回答。";
    } else if (!self.done && !self.stopped && !self.failure) {
        [self.decoder finish];
        self.failure = error.localizedDescription ?: self.decoder.error.localizedDescription ?: @"流式响应未正常结束，请重新生成。";
    }
    [self updateReply];
    NSString *status = self.stopped ? @"已停止生成" : self.failure;
    if (!status && !self.answer.length) status = @"服务返回了空回答，请重新生成。";
    if (status) self.reply.text = self.answer.length ? [self.answer stringByAppendingFormat:@"\n\n〔%@〕", status] : status;
    [session finishTasksAndInvalidate]; self.session = nil; self.task = nil; self.decoder = nil; self.body = nil;
    [self.sendButton setTitle:@"发送" forState:UIControlStateNormal];
    self.sendButton.accessibilityLabel = @"发送";
}
- (void)updatePlaceholder { self.placeholder.hidden = self.input.text.length > 0; }
- (void)textViewDidChange:(UITextView *)textView { [self updatePlaceholder]; }
- (void)clearAttachment {
    self.attachment = nil; self.chip.image = nil; self.chip.hidden = YES; self.chipContainer.hidden = YES;
}
- (void)attachments {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"添加图片" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"相册" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        PHPickerConfiguration *config = [PHPickerConfiguration new]; config.filter = PHPickerFilter.imagesFilter; config.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"图片文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
        picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"拍照" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (![NSBundle.mainBundle objectForInfoDictionaryKey:@"NSCameraUsageDescription"]) {
            [self message:@"当前宿主不支持相机授权，请先用系统相机拍照，再从相册添加。"]; return;
        }
        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) { [self message:@"当前环境无法打开相机。"]; return; }
        UIImagePickerController *picker = [UIImagePickerController new]; picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.input;
    sheet.popoverPresentationController.sourceRect = self.input.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)acceptImage:(UIImage *)image {
    if (!image.CGImage) { [self message:@"无法读取这张图片。"]; return; }
    self.attachment = image; self.chip.image = image; self.chip.hidden = NO; self.chipContainer.hidden = NO;
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (!provider) return;
    if (![provider canLoadObjectOfClass:UIImage.class]) { [self message:@"请选择可读取的图片。"]; return; }
    [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self acceptImage:[object isKindOfClass:UIImage.class] ? (UIImage *)object : nil]; });
    }];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL access = [url startAccessingSecurityScopedResource];
    NSNumber *size = nil; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    UIImage *image = size.unsignedLongLongValue <= 12 * 1024 * 1024 ? [UIImage imageWithContentsOfFile:url.path] : nil;
    if (access) [url stopAccessingSecurityScopedResource];
    [self acceptImage:image];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{ [self acceptImage:image]; }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
@end
