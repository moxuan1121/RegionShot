#import "RSRecognitionController.h"
#import <Vision/Vision.h>

@implementation RSRecognitionController {
    UIImage *_image;
    BOOL _barcode;
    UITextView *_text;
    VNRequest *_request;
    BOOL _closed;
}
- (instancetype)initWithImage:(UIImage *)image barcode:(BOOL)barcode {
    if ((self = [super init])) { _image = image; _barcode = barcode; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _barcode ? @"二维码 / 条码" : @"识别文字";
    _text = [UITextView new]; _text.editable = NO;
    _text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _text.adjustsFontForContentSizeCategory = YES;
    _text.text = @"正在识别…";
    _text.backgroundColor = UIColor.systemBackgroundColor;
    self.view = _text;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(copyText)];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    if (_barcode) _request = [VNDetectBarcodesRequest new];
    else {
        VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.recognitionLanguages = @[@"zh-Hans", @"zh-Hant", @"en-US"];
        request.usesLanguageCorrection = YES;
        _request = request;
    }
    VNRequest *request = _request;
    UIImage *image = _image;
    BOOL barcode = _barcode;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
            BOOL success = [handler performRequests:@[request] error:&error];
            NSMutableArray<NSString *> *strings = [NSMutableArray array];
            if (success) {
                for (VNObservation *observation in request.results) {
                    NSString *text = nil;
                    if (barcode && [observation isKindOfClass:VNBarcodeObservation.class])
                        text = ((VNBarcodeObservation *)observation).payloadStringValue;
                    else if ([observation isKindOfClass:VNRecognizedTextObservation.class])
                        text = [((VNRecognizedTextObservation *)observation) topCandidates:1].firstObject.string;
                    if (text.length) [strings addObject:text];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                RSRecognitionController *controller = weakSelf;
                if (!controller || controller->_closed) return;
                controller->_text.text = error ? error.localizedDescription : strings.count ?
                    [strings componentsJoinedByString:@"\n\n"] : @"没有识别到内容，请调整选区后重试。";
                controller.navigationItem.rightBarButtonItem.enabled = strings.count > 0 && !error;
                controller->_image = nil;
            });
        }
    });
}
- (void)copyText { UIPasteboard.generalPasteboard.string = _text.text; }
- (void)close { _closed = YES; [_request cancel]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)dealloc { [_request cancel]; }
@end
