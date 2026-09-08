#import "RSBehaviorSettings.h"
#import "RSOptions.h"

@implementation RSBehaviorSettings
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"截图与功能设置"; RSReloadOptions(); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return RSOptionGroups().count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [RSOptionGroups()[section][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return RSOptionGroups()[section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return RSOptionGroups()[section][@"footer"]; }
- (NSDictionary *)optionAt:(NSIndexPath *)path { return RSOptionGroups()[path.section][@"items"][path.row]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *option = [self optionAt:path];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = option[@"title"]; cell.textLabel.numberOfLines = 0;
    id value = RSOption(option[@"key"]);
    if ([option[@"default"] isKindOfClass:NSNumber.class] && !option[@"min"]) {
        UISwitch *toggle = [UISwitch new]; toggle.on = [value boolValue]; toggle.accessibilityIdentifier = option[@"key"];
        toggle.accessibilityLabel = option[@"title"];
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else { cell.detailTextLabel.text = [value description]; cell.detailTextLabel.numberOfLines = 2; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    return cell;
}
- (void)toggled:(UISwitch *)toggle { RSSetOption(toggle.accessibilityIdentifier, @(toggle.on)); [self.tableView reloadData]; }
- (void)invalidValue:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未保存" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSDictionary *option = [self optionAt:path];
    BOOL number = option[@"min"] != nil;
    if (!number && [option[@"default"] isKindOfClass:NSNumber.class]) return;
    NSString *message = number ? [NSString stringWithFormat:@"范围 %@–%@", option[@"min"], option[@"max"]] : [NSString stringWithFormat:@"最多 %@ 字符", option[@"limit"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:option[@"title"] message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [RSOption(option[@"key"]) description];
        field.keyboardType = number ? UIKeyboardTypeDecimalPad : UIKeyboardTypeDefault;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        RSSetOption(option[@"key"], option[@"default"]); [tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        id value = text;
        if (number) {
            NSScanner *scanner = [NSScanner scannerWithString:text]; double parsed;
            if (![scanner scanDouble:&parsed] || !scanner.isAtEnd) { [self invalidValue:@"请输入有效数字。"]; return; }
            value = @(parsed);
        } else if (text.length > [option[@"limit"] unsignedIntegerValue]) { [self invalidValue:message]; return; }
        RSSetOption(option[@"key"], value); [tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
