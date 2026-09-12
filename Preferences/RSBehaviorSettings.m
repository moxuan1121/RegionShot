#import "RSBehaviorSettings.h"
#import "RSOptions.h"
#import "../AI/RSAISettingsController.h"

@implementation RSBehaviorSettings
- (instancetype)init { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _groupIndex = NSNotFound; return self; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = self.groupIndex == NSNotFound ? @"功能设置" : RSOptionGroups()[self.groupIndex][@"title"]; RSReloadOptions(); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.groupIndex == NSNotFound ? RSOptionGroups().count - 1 : 1; }
- (BOOL)isAIGroup { return self.groupIndex == RSOptionGroups().count - 1; }
- (BOOL)isPhrasesPath:(NSIndexPath *)path { return self.isAIGroup && path.row == [RSOptionGroups()[self.groupIndex][@"items"] count]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.groupIndex == NSNotFound ? 1 : [RSOptionGroups()[self.groupIndex][@"items"] count] + (self.isAIGroup ? 1 : 0); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.groupIndex == NSNotFound ? nil : RSOptionGroups()[self.groupIndex][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return self.groupIndex == NSNotFound ? nil : RSOptionGroups()[self.groupIndex][@"footer"]; }
- (NSDictionary *)optionAt:(NSIndexPath *)path { return RSOptionGroups()[self.groupIndex][@"items"][path.row]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (self.groupIndex == NSNotFound) {
        UITableViewCell *category = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        category.textLabel.text = RSOptionGroups()[path.section][@"title"];
        category.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return category;
    }
    if ([self isPhrasesPath:path]) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"短语"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
    }
    NSDictionary *option = [self optionAt:path];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = option[@"title"]; cell.textLabel.numberOfLines = 0;
    if (option[@"readOnlyText"]) {
        cell.detailTextLabel.text = option[@"readOnlyText"]; cell.detailTextLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
    }
    id value = RSOption(option[@"key"]);
    if ([option[@"default"] isKindOfClass:NSNumber.class] && !option[@"min"]) {
        UISwitch *toggle = [UISwitch new]; toggle.on = [value boolValue]; toggle.accessibilityIdentifier = option[@"key"];
        toggle.accessibilityLabel = option[@"title"];
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else {
        NSArray *choices = option[@"choices"];
        NSArray *choiceValues = option[@"choiceValues"];
        if (choices.count) {
            NSUInteger index = choiceValues.count ? [choiceValues indexOfObject:value] : (NSUInteger)[value integerValue];
            if (index == NSNotFound && choiceValues.count) index = 0;
            cell.detailTextLabel.text = choices.count > index ? choices[index] : [value description];
        } else cell.detailTextLabel.text = [value description];
        cell.detailTextLabel.numberOfLines = 2; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
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
    if (self.groupIndex == NSNotFound) {
        RSBehaviorSettings *page = [RSBehaviorSettings new]; page.groupIndex = path.section;
        [self.navigationController pushViewController:page animated:YES]; return;
    }
    if ([self isPhrasesPath:path]) { [self.navigationController pushViewController:RSAICreatePhrasesController() animated:YES]; return; }
    NSDictionary *option = [self optionAt:path];
    if (option[@"readOnlyText"]) return;
    NSArray *choices = option[@"choices"];
    if (choices.count) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:option[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [choices enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
            [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                NSArray *choiceValues = option[@"choiceValues"];
                RSSetOption(option[@"key"], choiceValues.count > index ? choiceValues[index] : @(index)); [tableView reloadData];
            }]];
        }];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:path];
        sheet.popoverPresentationController.sourceRect = sheet.popoverPresentationController.sourceView.bounds;
        [self presentViewController:sheet animated:YES completion:nil]; return;
    }
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
