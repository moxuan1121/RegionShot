#import "RSRecognitionController.h"
#import "../Capture/RSRecognition.h"
#import "../Preferences/RSOptions.h"
#import "../AI/RSChatController.h"

@implementation RSRecognitionController {
    UIImage *_image;
    UITextView *_text;
    VNRequest *_request;
    BOOL _closed;
    BOOL _hasResult;
}
- (instancetype)initWithImage:(UIImage *)image {
    if ((self = [super init])) { _image = image; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"二维码 / 条码";
    _text = [UITextView new]; _text.editable = NO;
    _text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _text.adjustsFontForContentSizeCategory = YES;
    _text.text = @"正在识别…";
    _text.backgroundColor = UIColor.systemBackgroundColor;
    self.view = _text;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(copyText)];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    NSMutableArray *actions = [NSMutableArray array];
    NSArray *symbols = @[@"character.textbox", @"text.bubble", @"square.and.arrow.up"];
    NSArray *titles = @[@"分词", @"文字问答", @"分享文字"];
    SEL selectors[] = {@selector(segmentText), @selector(askAI), @selector(shareText)};
    for (NSUInteger i = 0; i < symbols.count; i++) {
        if (i) [actions addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
        UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:symbols[i]] style:UIBarButtonItemStylePlain target:self action:selectors[i]];
        button.accessibilityLabel = titles[i]; button.enabled = NO; [actions addObject:button];
    }
    self.toolbarItems = actions; [self.navigationController setToolbarHidden:NO];
    _request = RSBarcodeRequest();
    VNRequest *request = _request;
    UIImage *image = _image;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
            [handler performRequests:@[request] error:&error];
            NSArray<NSString *> *strings = RSBarcodeStrings(image.CGImage, request.results);
            if (strings.count) error = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                RSRecognitionController *controller = weakSelf;
                if (!controller || controller->_closed) return;
                controller->_text.text = error ? error.localizedDescription : strings.count ?
                    [strings componentsJoinedByString:@"\n\n"] : @"没有识别到内容，请调整选区后重试。";
                controller.navigationItem.rightBarButtonItem.enabled = strings.count > 0 && !error;
                controller->_hasResult = strings.count > 0 && !error;
                controller->_text.editable = controller->_hasResult;
                for (UIBarButtonItem *item in controller.toolbarItems) item.enabled = controller->_hasResult;
                controller->_image = nil;
            });
        }
    });
}
- (NSString *)selectedText {
    if (!_hasResult) return @"";
    return _text.selectedRange.length ? [_text.text substringWithRange:_text.selectedRange] : _text.text;
}
- (void)copyText { UIPasteboard.generalPasteboard.string = [self selectedText]; }
- (void)shareText {
    if (![self selectedText].length) return;
    [self presentViewController:[[UIActivityViewController alloc] initWithActivityItems:@[[self selectedText]] applicationActivities:nil] animated:YES completion:nil];
}
- (void)segmentText {
    NSString *text = [self selectedText]; if (!text.length) return;
    NSMutableDictionary *request = [@{@"text":text, @"handled":@NO} mutableCopy];
    [NSNotificationCenter.defaultCenter postNotificationName:@"com.moxuan.regionshot.tokenize" object:request];
    if ([request[@"handled"] boolValue]) {
        _closed = YES;
        [self dismissViewControllerAnimated:NO completion:^{ if (self.onForward) self.onForward(); }];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"分词未接入" message:@"请安装支持 RegionShot 的 KeyboardAI 1.4.6 或更新版。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
- (void)forwardText:(NSString *)text send:(BOOL)send {
    if (!text.length) return;
    UIWindowScene *scene = self.view.window.windowScene; _closed = YES;
    [self dismissViewControllerAnimated:NO completion:^{
        if (self.onForward) self.onForward();
        [RSChatController showText:text scene:scene sendImmediately:send];
    }];
}
- (void)askAI { [self forwardText:[self selectedText] send:[RSOption(@"AIAutoText") boolValue]]; }
- (void)close { _closed = YES; [_request cancel]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)dealloc { [_request cancel]; }
@end
