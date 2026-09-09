#import "RSMarkupTextEditViewController.h"

@interface RSMarkupTextEditViewController ()
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISlider *sizeSlider;
@property (nonatomic, strong) UIColor *chosenColor;
@property (nonatomic) BOOL isKeyboardVisible;
@end

@implementation RSMarkupTextEditViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.chosenColor = self.initialColor ?: [UIColor whiteColor];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];

    UITapGestureRecognizer *dim = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleDimTap:)];
    dim.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:dim];

    self.panel = [[UIView alloc] initWithFrame:CGRectZero];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.98];
    self.panel.layer.cornerRadius = 16;
    [self.view addSubview:self.panel];
    [self setupPanelContent:self.panel];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
        name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
        name:UIKeyboardWillHideNotification object:nil];
}

- (void)setupPanelContent:(UIView *)panel {
    self.field = [[UITextField alloc] init];
    self.field.text = self.initialText ?: @"";
    self.field.placeholder = @"添加文字";
    self.field.textColor = UIColor.labelColor;
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    [panel addSubview:self.field];

    self.sizeSlider = [[UISlider alloc] init];
    self.sizeSlider.minimumValue = 10;
    self.sizeSlider.maximumValue = 80;
    self.sizeSlider.value = self.initialFontSize > 0 ? self.initialFontSize : 16;
    [self.sizeSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:self.sizeSlider];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:cancel];

    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeSystem];
    [confirm setTitle:@"确认" forState:UIControlStateNormal];
    [confirm addTarget:self action:@selector(confirmTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:confirm];

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:@"清空" forState:UIControlStateNormal];
    [clear addTarget:self action:@selector(clearTextTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:clear];

    // Simple manual layout (kept explicit for learning clarity).
    CGFloat w = 300, pad = 16;
    self.field.frame     = CGRectMake(pad, pad, w-2*pad, 40);
    self.sizeSlider.frame= CGRectMake(pad, 68, w-2*pad, 30);
    cancel.frame  = CGRectMake(pad, 108, 70, 36);
    clear.frame   = CGRectMake(w/2-35, 108, 70, 36);
    confirm.frame = CGRectMake(w-pad-70, 108, 70, 36);
    self.panel.bounds = CGRectMake(0, 0, w, 160);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self ensureTextKeyboard];
}

- (void)ensureTextKeyboard { [self.field becomeFirstResponder]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.isKeyboardVisible)
        self.panel.center = CGPointMake(self.view.bounds.size.width/2,
                                        self.view.bounds.size.height/2);
}

- (void)keyboardWillShow:(NSNotification *)n {
    self.isKeyboardVisible = YES;
    CGRect kb = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    kb = [self.view convertRect:kb fromView:nil];
    CGFloat targetY = MAX(self.view.safeAreaInsets.top + 80, CGRectGetMinY(kb) - 92);
    [UIView animateWithDuration:0.25 animations:^{
        self.panel.center = CGPointMake(self.view.bounds.size.width/2, targetY);
    }];
}

- (void)keyboardWillHide:(NSNotification *)n { self.isKeyboardVisible = NO; }

- (void)handleDimTap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self.view];
    if (!CGRectContainsPoint(self.panel.frame, p)) [self cancelTapped];
}

- (void)sliderChanged:(UISlider *)s {
    self.field.font = [UIFont systemFontOfSize:s.value];
}

- (void)colorTapped:(UIButton *)sender {
    self.chosenColor = sender.backgroundColor ?: [UIColor whiteColor];
}

- (void)clearTextTapped { self.field.text = @""; }

- (void)cancelTapped {
    if (self.completion) self.completion(nil);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)confirmTapped {
    NSString *t = [self.field.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    RSMarkupTextAnnotation *a = nil;
    if (t.length) {
        a = [RSMarkupTextAnnotation new];
        a.text = t;
        a.textColor = self.chosenColor;
        a.fontSize = self.sizeSlider.value;
        a.opacity = self.initialOpacity > 0 ? self.initialOpacity : 1.0;
        a.showBorder = self.initialBorder;
        a.showBackground = self.initialBackground;
        a.showShadow = self.initialShadow;
    }
    if (self.completion) self.completion(a);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
