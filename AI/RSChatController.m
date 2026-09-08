#import "RSChatController.h"
#import "RSSSEDecoder.h"
#import "RSAISettingsController.h"
#import "../KeyboardAI/RSKAInterface.h"
#import "../KeyboardAI/RSKACore.h"
#import "../Preferences/RSOptions.h"
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
    UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) RSChatWindow *host;
@property (nonatomic, weak) UIWindow *previousKey;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIStackView *chat;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UIImageView *chip;
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
@property (nonatomic, copy) NSString *personaPrompt;
@property (nonatomic) BOOL keyboardPresentation;
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
@implementation RSChatController
+ (void)showImage:(UIImage *)image scene:(UIWindowScene *)scene {
    NSAssert(NSThread.isMainThread, @"Chat UI requires main thread");
    RSKAClosePanel();
    if (RSActiveChat) {
        [RSActiveChat restore];
        RSActiveChat.attachment = image;
        RSActiveChat.chip.image = image;
        RSActiveChat.chip.hidden = image == nil;
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
+ (void)showImage:(UIImage *)image scene:(UIWindowScene *)scene persona:(NSDictionary *)persona {
    if (!image || !persona) return;
    BOOL keyboard = [persona[@"presentation"] isEqual:@"keyboardai"];
    if (keyboard && RSActiveChat) [RSActiveChat close];
    [self showImage:nil scene:scene];
    RSActiveChat.personaPrompt = persona[@"prompt"] ?: @"";
    if ([persona[@"presentation"] isEqual:@"keyboardai"] && [RSChatPreferences() stringForKey:@"AIEndpoint"].length) {
        RSChatController *chat = RSActiveChat;
        chat.host.hidden = YES; [chat.previousKey makeKeyWindow];
        __weak RSChatController *weakChat = chat;
        chat.keyboardPresentation = RSKABeginAnswer(persona[@"name"] ?: @"AI 助手", ^{ [weakChat close]; });
        if (!chat.keyboardPresentation) [chat.host makeKeyAndVisible];
    }
    RSActiveChat.input.text = @"请按当前人设处理这张图片。";
    RSActiveChat.attachment = image; RSActiveChat.chip.image = image; RSActiveChat.chip.hidden = NO;
    if (!RSActiveChat.task) [RSActiveChat send];
    else [RSActiveChat message:@"图片已放入当前对话，待本次回答结束后点击发送。"];
}
+ (void)showText:(NSString *)text scene:(UIWindowScene *)scene sendImmediately:(BOOL)send {
    [self showImage:nil scene:scene];
    RSActiveChat.input.text = text;
    if (send && !RSActiveChat.task) [RSActiveChat send];
}
+ (void)showServiceSettings {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
        if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)candidate; break; }
    [self showImage:nil scene:scene];
    RSChatController *chat = RSActiveChat;
    chat.card.hidden = YES; chat.view.backgroundColor = UIColor.clearColor;
    RSAISettingsController *settings = [[RSAISettingsController alloc] initWithSaved:^{ [chat close]; }];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [chat presentViewController:navigation animated:YES completion:nil];
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
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    self.card = [UIView new];
    self.card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.card.layer.cornerRadius = 28;
    self.card.clipsToBounds = YES;
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.card];
    UIStackView *content = [UIStackView new];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:content];
    self.modelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.modelButton addTarget:self action:@selector(settings) forControlEvents:UIControlEventTouchUpInside];
    [self updateModelTitle];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[self.modelButton,
        [self button:@"keyboard.chevron.compact.down" title:@"收起键盘" action:@selector(hideKeyboard)],
        [self button:@"minus" title:@"最小化" action:@selector(minimize)],
        [self button:@"xmark" title:@"关闭对话" action:@selector(close)]]];
    top.alignment = UIStackViewAlignmentCenter;
    top.spacing = 6;
    [content addArrangedSubview:top];
    self.chip = [[UIImageView alloc] initWithImage:self.attachment];
    self.chip.hidden = self.attachment == nil;
    self.chip.contentMode = UIViewContentModeScaleAspectFit;
    self.chip.userInteractionEnabled = YES;
    self.chip.accessibilityLabel = @"待发送图片，轻按移除";
    self.chip.accessibilityTraits = UIAccessibilityTraitButton;
    [self.chip addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearAttachment)]];
    [self.chip.heightAnchor constraintEqualToConstant:72].active = YES;
    [content addArrangedSubview:self.chip];
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
    self.input.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    self.input.layer.cornerRadius = 16;
    self.input.accessibilityLabel = @"输入问题";
    [self.input.heightAnchor constraintEqualToConstant:70].active = YES;
    self.sendButton = [self button:@"arrow.up.circle.fill" title:@"发送" action:@selector(send)];
    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.input, [self button:@"plus" title:@"添加图片" action:@selector(attachments)], self.sendButton]];
    bottom.alignment = UIStackViewAlignmentCenter;
    bottom.spacing = 6;
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
        [content.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:12],
        [content.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-12],
        [content.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:8],
        [content.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-12],
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
    [self.modelButton setTitle:model.length ? model : @"图片问答 · 配置" forState:UIControlStateNormal];
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
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
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
    if (RSActiveChat == self) RSActiveChat = nil;
}
- (void)message:(NSString *)message {
    if (self.keyboardPresentation) { RSKAUpdateAnswer(self.answer ?: @"", YES, message); return; }
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"RegionShot" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)settings {
    if (self.task) { [self message:@"请先停止当前回复再修改服务配置。"]; return; }
    __weak typeof(self) weakSelf = self;
    RSAISettingsController *settings = [[RSAISettingsController alloc] initWithSaved:^{ [weakSelf updateModelTitle]; [weakSelf applyAppearance]; }];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (UITextView *)addRow:(NSString *)text image:(UIImage *)image assistant:(BOOL)assistant index:(NSUInteger)index {
    UIStackView *row = [UIStackView new]; row.axis = UILayoutConstraintAxisVertical; row.spacing = 2;
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
    view.backgroundColor = assistant ? UIColor.tertiarySystemBackgroundColor : UIColor.systemBackgroundColor;
    view.layer.cornerRadius = 14;
    [row addArrangedSubview:view];
    if (assistant) {
        UIButton *regen = [self button:@"arrow.clockwise" title:@"重新回答" action:@selector(regenerate:)];
        UIButton *tokenize = [self button:@"character.textbox" title:@"分词" action:@selector(tokenize:)];
        UIButton *copy = [self button:@"doc.on.doc" title:@"复制回答" action:@selector(copyReply:)];
        for (UIButton *button in @[regen, tokenize, copy]) button.tag = index;
        UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[[UIView new], regen, tokenize, copy]];
        [row addArrangedSubview:actions];
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
    [self minimize];
    RSKAOpenTokens(text);
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
    if (!text.length) text = [RSOption(@"AIImagePrompt") length] ? RSOption(@"AIImagePrompt") : @"请描述图片内容。";
    NSMutableArray *content = [NSMutableArray arrayWithObject:@{@"type":@"text", @"text":text}];
    if (self.attachment) {
        NSData *jpeg = UIImageJPEGRepresentation(self.attachment, 0.85);
        if (!jpeg || jpeg.length > 12 * 1024 * 1024) { [self message:@"图片过大或无法读取，请使用小于 12 MB 的图片。"]; return; }
        NSString *url = [@"data:image/jpeg;base64," stringByAppendingString:[jpeg base64EncodedStringWithOptions:0]];
        [content addObject:@{@"type":@"image_url", @"image_url":@{@"url":url}}];
    }
    [self addRow:text image:self.attachment assistant:NO index:self.history.count];
    [self.history addObject:[@{@"role":@"user", @"content":content} mutableCopy]];
    self.input.text = @""; [self clearAttachment]; [self hideKeyboard];
    [self startRequest];
}
- (void)startRequest {
    NSUserDefaults *prefs = RSChatPreferences();
    NSURL *endpoint = [NSURL URLWithString:[prefs stringForKey:@"AIEndpoint"] ?: @""];
    if (![endpoint.scheme.lowercaseString isEqual:@"https"] || !endpoint.host.length || endpoint.user || endpoint.password || ![prefs stringForKey:@"AIModel"].length) {
        [self message:@"请先配置有效的 HTTPS 服务地址和模型。"]; return;
    }
    NSMutableArray *messages = self.history.mutableCopy;
    BOOL imageQuestion = NO;
    id lastContent = [self.history.lastObject objectForKey:@"content"];
    if ([lastContent isKindOfClass:NSArray.class]) for (id part in lastContent)
        if ([part isKindOfClass:NSDictionary.class] && [part[@"type"] isEqual:@"image_url"]) { imageQuestion = YES; break; }
    NSString *persona = self.personaPrompt ?: RSOption(@"AIPersona");
    if (!persona.length) persona = RSAIPersonaPrompt(imageQuestion);
    if (persona.length) [messages insertObject:@{@"role":@"system", @"content":persona} atIndex:0];
    NSError *error = nil;
    NSString *model = [prefs stringForKey:@"AIModel"] ?: @"";
    NSMutableDictionary *payload = [@{@"model":model, @"messages":messages, @"stream":RSOption(@"AIStream")} mutableCopy];
    if ([RSOption(@"AIFastResponse") boolValue] && RSKASupportsFastResponse(endpoint.absoluteString, model)) payload[@"enable_thinking"] = @NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (!data || data.length > 32 * 1024 * 1024) {
        [self message:error.localizedDescription ?: @"对话图片总量超过 32 MB，请关闭后开始新对话。"]; return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    request.HTTPMethod = @"POST"; request.HTTPBody = data; request.timeoutInterval = 120;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream, application/json" forHTTPHeaderField:@"Accept"];
    NSString *key = RSAIReadKey();
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
    if (!self.session) self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    self.task = [self.session dataTaskWithRequest:request];
    [self.sendButton setImage:[UIImage systemImageNamed:@"stop.circle.fill"] forState:UIControlStateNormal];
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
        BOOL firstPiece = self.answer.length == 0;
        [self.answer appendString:piece];
        if (firstPiece) { [self updateReply]; return; }
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
    if (self.keyboardPresentation) { RSKAUpdateAnswer(self.answer, NO, nil); self.history.lastObject[@"content"] = self.answer.copy; return; }
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
    if (self.keyboardPresentation) RSKAUpdateAnswer(self.answer, YES, status);
    self.task = nil; self.decoder = nil; self.body = nil;
    [self.sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill"] forState:UIControlStateNormal];
    self.sendButton.accessibilityLabel = @"发送";
}
- (void)clearAttachment { self.attachment = nil; self.chip.image = nil; self.chip.hidden = YES; }
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
    self.attachment = image; self.chip.image = image; self.chip.hidden = NO;
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
