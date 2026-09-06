#import "RSImageEditor.h"
#import <PencilKit/PencilKit.h>

@implementation RSImageEditor {
    UIImage *_image;
    UIImageView *_background;
    PKCanvasView *_canvas;
    PKToolPicker *_picker;
    void (^_completion)(UIImage *);
    CGSize _drawingSize;
}
- (instancetype)initWithImage:(UIImage *)image completion:(void (^)(UIImage *))completion {
    if ((self = [super init])) { _image = image; _completion = [completion copy]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"标记截图";
    self.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _background = [[UIImageView alloc] initWithImage:_image];
    _background.contentMode = UIViewContentModeScaleToFill;
    [self.view addSubview:_background];
    _canvas = [PKCanvasView new];
    _canvas.backgroundColor = UIColor.clearColor;
    _canvas.opaque = NO;
    _canvas.drawingPolicy = PKCanvasViewDrawingPolicyAnyInput;
    _canvas.scrollEnabled = NO;
    [self.view addSubview:_canvas];
    _picker = [PKToolPicker new];
    [_picker addObserver:_canvas];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.uturn.forward"] style:UIBarButtonItemStylePlain target:self action:@selector(redo)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.uturn.backward"] style:UIBarButtonItemStylePlain target:self action:@selector(undo)]];
    self.navigationItem.rightBarButtonItems[1].accessibilityLabel = @"重做";
    self.navigationItem.rightBarButtonItems[2].accessibilityLabel = @"撤销";
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    safe = CGRectInset(safe, 8, 8);
    safe.size.height = MAX(1, safe.size.height - 100);
    CGFloat factor = MIN(safe.size.width / _image.size.width, safe.size.height / _image.size.height);
    CGSize size = CGSizeMake(_image.size.width * factor, _image.size.height * factor);
    if (_drawingSize.width > 0 && !CGSizeEqualToSize(size, _drawingSize)) {
        _canvas.drawing = [_canvas.drawing drawingByApplyingTransform:CGAffineTransformMakeScale(size.width / _drawingSize.width, size.height / _drawingSize.height)];
    }
    _drawingSize = size;
    CGRect frame = CGRectMake(CGRectGetMidX(safe) - size.width / 2, CGRectGetMidY(safe) - size.height / 2, size.width, size.height);
    _background.frame = frame; _canvas.frame = frame;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_picker setVisible:YES forFirstResponder:_canvas];
    [_canvas becomeFirstResponder];
}
- (void)viewWillDisappear:(BOOL)animated {
    [_picker setVisible:NO forFirstResponder:_canvas];
    [_canvas resignFirstResponder];
    [super viewWillDisappear:animated];
}
- (void)undo { [_canvas.undoManager undo]; }
- (void)redo { [_canvas.undoManager redo]; }
- (void)cancel { _completion = nil; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)done {
    if (_drawingSize.width <= 0 || !_image.CGImage) return;
    self.navigationItem.rightBarButtonItems.firstObject.enabled = NO;
    CGFloat scale = (CGFloat)CGImageGetWidth(_image.CGImage) / _drawingSize.width;
    UIImage *drawing = [_canvas.drawing imageFromRect:(CGRect){CGPointZero, _drawingSize} scale:scale];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = _image.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:_image.size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [self->_image drawInRect:(CGRect){CGPointZero, self->_image.size}];
        [drawing drawInRect:(CGRect){CGPointZero, self->_image.size}];
    }];
    if (!image.CGImage) { self.navigationItem.rightBarButtonItems.firstObject.enabled = YES; return; }
    void (^completion)(UIImage *) = _completion; _completion = nil;
    [self dismissViewControllerAnimated:YES completion:^{ if (completion) completion(image); }];
}
- (void)dealloc { [_picker removeObserver:_canvas]; }
@end
