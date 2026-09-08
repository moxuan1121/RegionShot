#import <UIKit/UIKit.h>
#import "RSInputStore.h"
#import "RSInputInterface.h"
#import "RSInputOptions.h"

@interface RSInputOptionsController : UITableViewController <UIColorPickerViewControllerDelegate>
@property BOOL search;
@property(strong) NSMutableArray *engines;
@property(strong) NSMutableDictionary *prompt;
@property(copy) NSString *colorKey;
@end

@implementation RSInputOptionsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.search ? @"搜索引擎" : @"悬浮按钮与窗口";
    self.engines = [RSInputSearchEngines(RSInputConfig()) mutableCopy];
    self.prompt = [RSInputPromptOptions(RSInputConfig()) mutableCopy];
    if (self.search) self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addEngine)], self.editButtonItem];
}
- (void)error:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法保存" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)save {
    if (RSInputSaveOptions(self.search ? @"searchEngines" : @"prompt", self.search ? (id)self.engines : self.prompt)) return YES;
    self.engines = [RSInputSearchEngines(RSInputConfig()) mutableCopy];
    self.prompt = [RSInputPromptOptions(RSInputConfig()) mutableCopy];
    [self.tableView reloadData];
    [self error:@"配置未写入，请检查文件权限或缩短配置内容。"];
    return NO;
}
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView { return self.search ? 1 : 5; }
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.search ? self.engines.count : section == 0 ? 1 : section == 1 ? 3 : section == 2 ? 4 : section == 4 ? 4 : 2;
}
- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.search ? nil : @[@"复制后显示", @"位置与大小", @"按钮配色", @"按压动画", @"窗口最高高度"][section];
}
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.search) return @"点击编辑，左滑删除，点“编辑”拖动排序。第一项用于浮窗的搜索按钮。地址使用 %@ 代表搜索文字，支持网页及自定义应用协议。能否打开取决于已安装的应用。更改立即保存。";
    if (section == 4) return @"分别设置最高高度和窗口优先级。可输入 0–1,000,000,000；普通窗口约 1，状态栏上方约 1001，系统弹窗上方约 2001。1,000,000,000 表示系统最高层。相差 1 即可避免同层级排序。下次打开窗口生效。";
    return section == 0 ? @"轻按直接分词；长按显示搜索引擎和 AI 人设。更改立即保存，下次复制生效。" : section == 3 ? @"保留弹簧按压与收起动画，速度 1× 为原始速度。" : nil;
}
- (NSString *)keyForPath:(NSIndexPath *)path {
    return @[@[@"enabled"], @[@"size", @"height", @"duration"], @[@"gradient", @"startColor", @"middleColor", @"endColor"], @[@"animations", @"animationSpeed"],
        @[@"tokenMaxHeight", @"aiMaxHeight", @"tokenWindowPriority", @"aiWindowPriority"]][path.section][path.row];
}
- (UITableViewCell *)tableView:(__unused UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (self.search) {
        cell.textLabel.text = self.engines[path.row][@"name"];
        cell.detailTextLabel.text = self.engines[path.row][@"engine"];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSString *key = [self keyForPath:path];
    NSString *title = @{@"enabled": @"启用分词悬浮按钮", @"size": @"按钮大小", @"height": @"屏幕纵向位置", @"duration": @"显示时长", @"gradient": @"渐变配色", @"startColor": @"起始颜色", @"middleColor": @"中间颜色", @"endColor": @"结束颜色", @"animations": @"启用动画", @"animationSpeed": @"动画速度", @"tokenMaxHeight": @"分词窗口最高高度", @"aiMaxHeight": @"AI 窗口最高高度", @"tokenWindowPriority": @"分词窗口优先级", @"aiWindowPriority": @"AI 窗口优先级"}[key];
    cell.textLabel.text = title;
    if ([@[@"enabled", @"gradient", @"animations"] containsObject:key]) {
        UISwitch *toggle = [UISwitch new];
        toggle.accessibilityIdentifier = key;
        toggle.accessibilityLabel = title;
        toggle.on = [self.prompt[key] boolValue];
        [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([key hasSuffix:@"Color"]) {
        cell.detailTextLabel.text = [@"#" stringByAppendingString:self.prompt[key]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([key hasSuffix:@"WindowPriority"]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lld", [self.prompt[key] longLongValue]];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        UISlider *slider = [UISlider new];
        NSArray *range = @{@"size": @[@60, @160], @"height": @[@10, @90], @"duration": @[@0.5, @3], @"animationSpeed": @[@0.5, @2], @"tokenMaxHeight": @[@30, @90], @"aiMaxHeight": @[@30, @90]}[key];
        slider.minimumValue = [range[0] floatValue];
        slider.maximumValue = [range[1] floatValue];
        slider.value = [self.prompt[key] floatValue];
        slider.accessibilityIdentifier = key;
        slider.accessibilityLabel = title;
        slider.continuous = NO;
        [slider addTarget:self action:@selector(slide:) forControlEvents:UIControlEventValueChanged];
        UILabel *label = [UILabel new];
        NSString *unit = [key isEqualToString:@"duration"] ? @"秒" : [key isEqualToString:@"animationSpeed"] ? @"×" : @"%";
        label.text = [NSString stringWithFormat:@"%@  %.1f%@", title, slider.value, unit];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, slider]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        cell.textLabel.text = nil;
        [cell.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12]]];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}
- (void)toggle:(UISwitch *)sender { self.prompt[sender.accessibilityIdentifier] = @(sender.on); [self save]; }
- (void)slide:(UISlider *)sender {
    self.prompt[sender.accessibilityIdentifier] = @(sender.value);
    [self save];
    [self.tableView reloadData];
}
- (void)addEngine { [self editEngine:NSNotFound]; }
- (void)editEngine:(NSUInteger)index {
    if (index == NSNotFound && self.engines.count >= 12) { [self error:@"最多 12 个搜索引擎。 "]; return; }
    NSDictionary *entry = index == NSNotFound ? @{} : self.engines[index];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"搜索引擎" message:@"网址示例：https://www.google.com/search?q=%@\nsnssdk1128://search/result?keyword=%@" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"名称（最多 30 字符）"; field.text = entry[@"name"]; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"搜索网址，包含 %@"; field.text = entry[@"engine"];
        field.keyboardType = UIKeyboardTypeURL; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSDictionary *item = @{@"name": weakAlert.textFields[0].text ?: @"", @"engine": weakAlert.textFields[1].text ?: @""};
        if (!RSInputValidEngines(@[item])) { [self error:@"请检查名称和地址，地址需包含协议及 %@ 搜索占位符。 "]; return; }
        if (index == NSNotFound) [self.engines addObject:item]; else self.engines[index] = item;
        [self save]; [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (self.search) { [self editEngine:path.row]; return; }
    NSString *key = [self keyForPath:path];
    if ([key hasSuffix:@"WindowPriority"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置窗口优先级"
            message:@"输入 0–1,000,000,000 的整数。普通约 1，状态栏上方约 1001，系统弹窗上方约 2001；1,000,000,000 表示系统最高层。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = [NSString stringWithFormat:@"%lld", [self.prompt[key] longLongValue]];
            field.keyboardType = UIKeyboardTypeNumberPad;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak UIAlertController *weakAlert = alert;
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSScanner *scanner = [NSScanner scannerWithString:weakAlert.textFields.firstObject.text ?: @""];
            long long value = 0;
            if (![scanner scanLongLong:&value] || !scanner.isAtEnd || value < 0 || value > 1000000000LL) {
                [self error:@"请输入 0–1,000,000,000 之间的整数。"];
                return;
            }
            self.prompt[key] = @(value);
            [self save];
            [self.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (![key hasSuffix:@"Color"]) return;
    self.colorKey = key;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:self.prompt[key]] scanHexInt:&rgb];
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.selectedColor = [UIColor colorWithRed:((rgb >> 16) & 255)/255.0 green:((rgb >> 8) & 255)/255.0 blue:(rgb & 255)/255.0 alpha:1];
    picker.supportsAlpha = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    CGFloat red, green, blue, alpha;
    if ([picker.selectedColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
        self.prompt[self.colorKey] = [NSString stringWithFormat:@"%02X%02X%02X", (unsigned)lround(red*255), (unsigned)lround(green*255), (unsigned)lround(blue*255)];
        [self save]; [self.tableView reloadData];
    }
}
- (BOOL)tableView:(__unused UITableView *)tableView canEditRowAtIndexPath:(__unused NSIndexPath *)path { return self.search; }
- (BOOL)tableView:(__unused UITableView *)tableView canMoveRowAtIndexPath:(__unused NSIndexPath *)path { return self.search; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    if (self.engines.count == 1) { [self error:@"请至少保留一个搜索引擎。 "]; return; }
    [self.engines removeObjectAtIndex:path.row]; [self save]; [tableView reloadData];
}
- (void)tableView:(__unused UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSDictionary *entry = self.engines[from.row];
    [self.engines removeObjectAtIndex:from.row]; [self.engines insertObject:entry atIndex:to.row]; [self save];
}
@end
UIViewController *RSInputCreateOptions(BOOL search) {
    RSInputOptionsController *controller = [[RSInputOptionsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.search = search;
    return controller;
}

@interface RSSileoSettings : UITableViewController @end
@implementation RSSileoSettings
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Sileo 介绍页翻译"; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : RSInputActions().count + 1; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"长按插件介绍文字" : @"翻译使用的人设"; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { return section == 0 ? @"只在 Sileo 插件介绍页启用。长按文字后提交到已配置的 AI 服务，不自动读取聊天或其他页面。" : nil; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSDictionary *settings = RSInputConfig()[@"sileo"];
    if (path.section == 0) { cell.textLabel.text = @"启用介绍页翻译"; UISwitch *toggle = [UISwitch new]; toggle.on = [settings[@"enabled"] boolValue]; [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; }
    else { NSString *title = path.row ? RSInputActions()[path.row - 1][@"title"] : @""; cell.textLabel.text = title.length ? title : @"默认中文翻译"; cell.accessoryType = [title isEqual:settings[@"personaTitle"] ?: @""] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; }
    return cell;
}
- (void)write:(NSString *)key value:(id)value {
    NSMutableDictionary *settings = [RSInputConfig()[@"sileo"] mutableCopy] ?: [NSMutableDictionary dictionary]; settings[key] = value;
    if (!RSInputSaveOptions(@"sileo", settings)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未保存" message:@"无法写入 Sileo 翻译设置，请检查权限。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    }
    [self.tableView reloadData];
}
- (void)toggle:(UISwitch *)toggle { [self write:@"enabled" value:@(toggle.on)]; }
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path { [table deselectRowAtIndexPath:path animated:YES]; if (path.section == 1) [self write:@"personaTitle" value:path.row ? RSInputActions()[path.row - 1][@"title"] : @""]; }
@end
UIViewController *RSCreateSileoSettings(void) { return [[RSSileoSettings alloc] initWithStyle:UITableViewStyleInsetGrouped]; }
