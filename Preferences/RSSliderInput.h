#import <UIKit/UIKit.h>
static inline UIView *RSSliderInput(UISlider *slider, UIViewController *owner) {
    UIButton *edit = [UIButton buttonWithType:UIButtonTypeSystem];
    [edit setImage:[UIImage systemImageNamed:@"keyboard"] forState:UIControlStateNormal];
    edit.accessibilityLabel = @"键入数值";
    [edit.widthAnchor constraintEqualToConstant:44].active = YES;
    __weak UIViewController *weakOwner = owner;
    __weak UISlider *weakSlider = slider;
    [edit addAction:[UIAction actionWithHandler:^(UIAction *action) {
        UISlider *control = weakSlider; if (!control) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:control.accessibilityLabel ?: @"键入数值" message:[NSString stringWithFormat:@"范围 %g–%g", control.minimumValue, control.maximumValue] preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = [NSString stringWithFormat:@"%g", control.value]; field.keyboardType = UIKeyboardTypeNumbersAndPunctuation; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak UIAlertController *weakAlert = alert;
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *item) {
            NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSScanner *scanner = [NSScanner scannerWithString:text]; double value;
            if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) || value < control.minimumValue || value > control.maximumValue) {
                UIAlertController *error = [UIAlertController alertControllerWithTitle:@"数值未修改" message:@"请输入范围内的有效数字。" preferredStyle:UIAlertControllerStyleAlert];
                [error addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
                [weakOwner presentViewController:error animated:YES completion:nil]; return;
            }
            control.value = value; [control sendActionsForControlEvents:UIControlEventValueChanged];
        }]];
        [weakOwner presentViewController:alert animated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[slider, edit]];
    row.spacing = 6; row.alignment = UIStackViewAlignmentCenter; row.frame = CGRectMake(0, 0, 190, 44);
    return row;
}
