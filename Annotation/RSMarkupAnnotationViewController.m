#import "RSMarkupAnnotationViewController.h"
#import "RSMarkupAnnotationCanvas.h"
#import "RSMarkupColorPickerView.h"
#import "RSMarkupTextEditViewController.h"
#import <Photos/Photos.h>
#import <objc/runtime.h>

@interface RSMarkupAnnotationViewController () <UIGestureRecognizerDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, strong) UIScrollView *zoomView;
@property (nonatomic, strong) UIView *zoomContentView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) RSMarkupAnnotationCanvas *canvas;
@property (nonatomic, strong) UIView *toolbar;
@property (nonatomic, strong) RSMarkupColorPickerView *colorPicker;
@property (nonatomic, strong) NSMutableArray<UIButton *> *modeButtons;
@property (nonatomic) BOOL isAddingText;
// 1.6 新增：预设线宽条
@property (nonatomic, strong) UIView *widthBar;
@property (nonatomic, strong) UILabel *thinLabel;
@property (nonatomic, strong) UILabel *thickLabel;
@property (nonatomic, strong) NSMutableArray<UIButton *> *presetButtons;
@property (nonatomic, strong) UISlider *widthSlider;
@property (nonatomic, strong) UITapGestureRecognizer *textTap;
@end

@implementation RSMarkupAnnotationViewController

- (instancetype)initWithImage:(UIImage *)image {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _sourceImage = image;
        _modeButtons = [NSMutableArray array];
    }
    return self;
}

#pragma mark - Window lifecycle

- (void)closeAnimated { if (self.dismissEditor) self.dismissEditor(); else [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)finish {
    UIImage *image = [self compositeImage];
    if (!image) return;
    UIPasteboard.generalPasteboard.image = image;
    void (^callback)(UIImage *) = self.completion;
    self.completion = nil;
    [self closeAnimated];
    if (callback) callback(image);
}

#pragma mark - View setup

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.clearColor;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    glass.frame = self.view.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:glass];
    UIView *shade = [[UIView alloc] initWithFrame:self.view.bounds];
    shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    shade.userInteractionEnabled = NO;
    [self.view addSubview:shade];
    self.title = @"标记截图";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(closeAnimated)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(finish)];

    self.zoomView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.zoomView.delegate = self;
    self.zoomView.minimumZoomScale = 1.0;
    self.zoomView.maximumZoomScale = 6.0;
    self.zoomView.bouncesZoom = YES;
    self.zoomView.showsHorizontalScrollIndicator = NO;
    self.zoomView.showsVerticalScrollIndicator = NO;
    self.zoomView.delaysContentTouches = NO;
    self.zoomView.panGestureRecognizer.minimumNumberOfTouches = 2;
    [self.view addSubview:self.zoomView];

    self.zoomContentView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.zoomView addSubview:self.zoomContentView];

    self.imageView = [[UIImageView alloc] initWithImage:self.sourceImage];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    self.imageView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    [self.zoomContentView addSubview:self.imageView];

    self.canvas = [[RSMarkupAnnotationCanvas alloc] initWithFrame:CGRectZero];
    self.canvas.sourceImage = self.sourceImage;
    [self.zoomContentView addSubview:self.canvas];

    self.textTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTextPlacement:)];
    self.textTap.enabled = NO;
    self.textTap.cancelsTouchesInView = NO;
    [self.canvas addGestureRecognizer:self.textTap];

    [self setupToolbar];
    [self setupWidthBar];   // 1.6 新增：预设线宽条

    self.colorPicker = [[RSMarkupColorPickerView alloc] initWithFrame:CGRectZero];
    self.colorPicker.hidden = YES;
    __weak typeof(self) ws = self;
    self.colorPicker.colorSelected = ^(UIColor *c){ ws.canvas.strokeColor = c; };
    self.colorPicker.widthChanged  = ^(CGFloat w){ ws.canvas.lineWidth = w; };
    [self.view addSubview:self.colorPicker];

    [self setArrowMode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat toolH = 96 + self.view.safeAreaInsets.bottom;
    CGRect box = CGRectMake(0, self.view.safeAreaInsets.top, b.size.width,
                            b.size.height - toolH - self.view.safeAreaInsets.top);
    CGRect disp = [self imageDisplayRectInBox:box];
    CGSize oldSize = self.zoomContentView.bounds.size;
    if (!CGSizeEqualToSize(oldSize, disp.size)) {
        self.zoomView.zoomScale = 1.0;
        [self.canvas resizeDrawingToSize:disp.size];
        self.zoomView.contentSize = disp.size;
        self.zoomContentView.frame = (CGRect){CGPointZero, disp.size};
        self.imageView.frame = self.zoomContentView.bounds;
        self.canvas.frame = self.zoomContentView.bounds;
        self.canvas.imageDisplayRect = self.zoomContentView.bounds;
    }
    self.zoomView.frame = disp;
    self.toolbar.frame = CGRectMake(0, b.size.height - toolH, b.size.width, toolH);
    [self layoutToolbarButtons];
    self.colorPicker.frame = CGRectMake(10, b.size.height - toolH - 108,
                                        b.size.width - 20, 100);

    // 1.6 新增：粗细条布局（在工具栏正上方一条）
    CGFloat barH = 48;
    self.widthBar.frame = CGRectMake(10, b.size.height - toolH - barH - 8,
                                     b.size.width - 20, barH);
    CGFloat pad = 12, y = (barH - 30) / 2;
    self.thinLabel.frame  = CGRectMake(pad, 0, 24, barH);
    self.thickLabel.frame = CGRectMake(self.widthBar.bounds.size.width - pad - 24, 0, 24, barH);
    CGFloat x = pad + 30;
    CGFloat presetW = 34;
    for (UIButton *pb in self.presetButtons) {
        pb.frame = CGRectMake(x, y, presetW, 30);
        x += presetW + 4;
    }
    CGFloat slX = x + 6;
    CGFloat slW = self.widthBar.bounds.size.width - slX - pad - 30;
    if (slW < 40) slW = 40;
    self.widthSlider.frame = CGRectMake(slX, y, slW, 30);
}

// Compute where an aspect-fit image lands in the editor's available box.
- (CGRect)imageDisplayRectInBox:(CGRect)box {
    CGSize img = self.sourceImage.size;
    if (img.width <= 0 || img.height <= 0) return box;
    CGFloat s = MIN(box.size.width/img.width, box.size.height/img.height);
    CGSize d = CGSizeMake(img.width*s, img.height*s);
    return CGRectMake(box.origin.x + (box.size.width-d.width)/2,
                      box.origin.y + (box.size.height-d.height)/2, d.width, d.height);
}

#pragma mark - Detail zoom

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.zoomContentView;
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
    [self.canvas cancelCurrentStroke];
}

#pragma mark - Toolbar

- (void)setupToolbar {
    self.toolbar = [[UIView alloc] initWithFrame:CGRectZero];
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:blur];
    bg.frame = self.toolbar.bounds;
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.toolbar addSubview:bg];
    [self.view addSubview:self.toolbar];

    NSArray *specs = @[
        @[@"arrow.up.right", @"setArrowMode"],
        @[@"square", @"setRectMode"],
        @[@"circle", @"setCircleMode"],
        @[@"scribble", @"setScribbleMode"],
        @[@"square.grid.2x2", @"setMosaicMode"],
        @[@"magnifyingglass.circle", @"setMagnifierMode"],
        @[@"viewfinder.circle", @"setHighlightMode"],
        @[@"textformat", @"addTextMode"],
        @[@"paintpalette", @"toggleColorPicker"],
        @[@"arrow.uturn.backward", @"undo"],
        @[@"trash", @"clearAllAnnotations"],
        @[@"square.and.arrow.down", @"saveToAlbum"],
        @[@"doc.on.doc", @"copyToClipboard"],
        @[@"square.and.arrow.up", @"airDropTapped"],
        @[@"lineweight", @"toggleWidthBar"],
        @[@"xmark", @"closeAnimated"],
    ];
    for (NSArray *spec in specs) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *img = [UIImage systemImageNamed:spec[0]];
        [btn setImage:img forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        SEL sel = NSSelectorFromString(spec[1]);
        [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [self.toolbar addSubview:btn];
        // Track only the mode buttons for highlight.
        if ([spec[1] hasPrefix:@"set"] || [spec[1] isEqual:@"addTextMode"])
            [self.modeButtons addObject:btn];
        objc_setAssociatedObject(btn, "sel", spec[1], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self layoutToolbarButtons];
}

- (void)layoutToolbarButtons {
    NSArray *btns = self.toolbar.subviews;
    NSUInteger n = 0;
    for (UIView *v in btns) if ([v isKindOfClass:UIButton.class]) n++;
    if (!n) return;
    NSUInteger columns = (n + 1) / 2;
    CGFloat w = self.toolbar.bounds.size.width / columns;
    NSUInteger i = 0;
    for (UIView *v in btns) {
        if (![v isKindOfClass:UIButton.class]) continue;
        v.frame = CGRectMake((i % columns)*w, (i / columns)*48, w, 48);
        i++;
    }
}

- (void)updateModeButtons {
    NSArray<NSNumber *> *modes = @[@0,@1,@2,@3,@4,@5,@7,@6];
    self.textTap.enabled = self.isAddingText;
    for (NSUInteger i = 0; i < self.modeButtons.count; i++)
        self.modeButtons[i].tintColor = modes[i].integerValue == self.canvas.drawMode ? UIColor.systemYellowColor : UIColor.whiteColor;
}

#pragma mark - Modes

- (void)setArrowMode      { self.canvas.drawMode = RSMarkupDrawModeArrow;     self.isAddingText = NO; [self updateModeButtons]; }
- (void)setRectMode       { self.canvas.drawMode = RSMarkupDrawModeRect;      self.isAddingText = NO; [self updateModeButtons]; }
- (void)setCircleMode     { self.canvas.drawMode = RSMarkupDrawModeCircle;    self.isAddingText = NO; [self updateModeButtons]; }
- (void)setScribbleMode   { self.canvas.drawMode = RSMarkupDrawModeScribble;  self.isAddingText = NO; [self updateModeButtons]; }
- (void)setMosaicMode     { self.canvas.drawMode = RSMarkupDrawModeMosaic;    self.isAddingText = NO; [self updateModeButtons]; }
- (void)setMagnifierMode  { self.canvas.drawMode = RSMarkupDrawModeMagnifier; self.isAddingText = NO; [self updateModeButtons]; }
- (void)addTextMode       { self.canvas.drawMode = RSMarkupDrawModeText;      self.isAddingText = YES; [self updateModeButtons]; }
- (void)setHighlightMode  { self.canvas.drawMode = RSMarkupDrawModeHighlight; self.isAddingText = NO; [self updateModeButtons];
                            [self showToast:@"拖拽框选高亮区域(圆角),周边半透明"]; }  // 1.6 新增

- (void)toggleColorPicker { self.widthBar.hidden = YES; self.colorPicker.hidden = !self.colorPicker.hidden; }
- (void)hideColorPicker   { self.colorPicker.hidden = YES; }

#pragma mark - Preset widths (1.6 新增：预设线宽 + 滑块，"粗/细")

// 预设线宽档位数组（对应 1.6 的 _presetWidths）。
- (NSArray<NSNumber *> *)presetWidths {
    return @[@2.0, @5.0, @9.0, @14.0, @20.0];
}

// 底部"粗细条"：左"细"、右"粗"，中间一排预设档 + 一个无级滑块。
- (void)setupWidthBar {
    UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
    bar.tag = 0x5757; // 'WW'
    bar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
    bar.layer.cornerRadius = 12.0;
    [self.view addSubview:bar];
    self.widthBar = bar;
    self.widthBar.hidden = YES;

    UILabel *lblThin = [self barLabel:@"细"];
    UILabel *lblThick = [self barLabel:@"粗"];
    [bar addSubview:lblThin];
    [bar addSubview:lblThick];
    self.thinLabel = lblThin;
    self.thickLabel = lblThick;

    // 预设档按钮
    self.presetButtons = [NSMutableArray array];
    NSArray<NSNumber *> *ws = [self presetWidths];
    for (NSUInteger i = 0; i < ws.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:[NSString stringWithFormat:@"%.0f", ws[i].doubleValue] forState:UIControlStateNormal];
        b.tintColor = [UIColor whiteColor];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(widthPresetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:b];
        [self.presetButtons addObject:b];
    }

    // 无级滑块
    UISlider *sl = [[UISlider alloc] init];
    sl.minimumValue = 1.0; sl.maximumValue = 24.0; sl.value = self.canvas.lineWidth;
    [sl addTarget:self action:@selector(widthSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [bar addSubview:sl];
    self.widthSlider = sl;
}

- (UILabel *)barLabel:(NSString *)t {
    UILabel *l = [[UILabel alloc] init];
    l.text = t; l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:14]; [l sizeToFit];
    return l;
}

- (void)toggleWidthBar { self.colorPicker.hidden = YES; self.widthBar.hidden = !self.widthBar.hidden; }

// 点预设档：直接套用该线宽（对应 1.6 widthPresetTapped:）。
- (void)widthPresetTapped:(UIButton *)sender {
    NSArray<NSNumber *> *ws = [self presetWidths];
    if (sender.tag < 0 || (NSUInteger)sender.tag >= ws.count) return;
    CGFloat w = ws[(NSUInteger)sender.tag].doubleValue;
    self.canvas.lineWidth = w;
    self.widthSlider.value = w;
}

// 拖滑块：无级调线宽（对应 1.6 widthSliderChanged: + floatValue）。
- (void)widthSliderChanged:(UISlider *)sender {
    self.canvas.lineWidth = sender.value;
}

#pragma mark - Text placement

- (void)handleTextPlacement:(UITapGestureRecognizer *)gesture {
    if (!self.isAddingText || gesture.state != UIGestureRecognizerStateEnded) return;
    [self showTextEditAtPoint:[gesture locationInView:self.canvas] text:@"" editIndex:-1];
}

- (void)showTextEditAtPoint:(CGPoint)point text:(NSString *)text editIndex:(NSInteger)idx {
    RSMarkupTextEditViewController *vc = [RSMarkupTextEditViewController new];
    vc.initialText = text;
    vc.initialColor = self.canvas.strokeColor;
    vc.initialFontSize = 16;
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    __weak typeof(self) ws = self;
    vc.completion = ^(RSMarkupTextAnnotation *a) {
        if (!a) return;
        a.center = point;
        RSMarkupAnnotationItem *item = [RSMarkupAnnotationItem new];
        item.type = RSMarkupDrawModeText; item.textAnnotation = a;
        [ws.canvas.items addObject:item]; [ws.canvas setNeedsDisplay];
        [ws showToast:@"已添加文字"];
    };
    [self presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Edit ops

- (void)undo { [self.canvas undo]; }

- (void)clearAllAnnotations {
    [self.canvas clearAll];
    [self showToast:@"已清空所有标记"];
}

#pragma mark - Export / save / share

- (UIImage *)compositeImage { return [self.canvas renderedImage]; }

- (void)saveToAlbum {
    UIImage *out = [self compositeImage];
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
                [self showToast:@"无相册权限"]; return;
            }
            UIImageWriteToSavedPhotosAlbum(out, self,
                @selector(image:didFinishSavingWithError:contextInfo:), NULL);
        });
    }];
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error
    contextInfo:(void *)ctx {
    [self showToast:error ? @"保存失败" : @"已保存到相册"];
}

- (void)copyToClipboard {
    [self finish];
}

- (void)airDropTapped {
    UIImage *out = [self compositeImage];
    UIActivityViewController *av = [[UIActivityViewController alloc]
        initWithActivityItems:@[out] applicationActivities:nil];
    av.popoverPresentationController.sourceView = self.toolbar;
    av.popoverPresentationController.sourceRect = self.toolbar.bounds;
    [self presentViewController:av animated:YES completion:nil];
}

- (BOOL)shouldAutorotate { return YES; }

#pragma mark - Toast

- (void)showToast:(NSString *)msg {
    UILabel *t = [[UILabel alloc] init];
    t.text = msg;
    t.textColor = [UIColor whiteColor];
    t.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    t.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    t.textAlignment = NSTextAlignmentCenter;
    t.numberOfLines = 0;
    t.lineBreakMode = NSLineBreakByWordWrapping;
    t.layer.cornerRadius = 14;
    t.clipsToBounds = YES;
    CGFloat w = MIN(320, self.view.bounds.size.width - 40);
    CGSize fit = [t sizeThatFits:CGSizeMake(w - 24, 80)];
    CGFloat h = MIN(80, MAX(40, fit.height + 16));
    t.frame = CGRectMake((self.view.bounds.size.width-w)/2,
                         self.view.bounds.size.height/2-h/2, w, h);
    t.alpha = 0;
    [self.view addSubview:t];
    [UIView animateWithDuration:0.2 animations:^{ t.alpha = 1; } completion:^(BOOL f){
        [UIView animateWithDuration:0.3 delay:1.0 options:0 animations:^{ t.alpha = 0; }
            completion:^(BOOL f2){ [t removeFromSuperview]; }];
    }];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
