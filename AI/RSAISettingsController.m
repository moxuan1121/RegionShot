#import "../Input/RSInputStore.h"
#import "RSAISettingsController.h"
#import "../Preferences/RSBehaviorSettings.h"
#import <notify.h>
extern UIViewController *RSCreateSileoSettings(void);
extern UIViewController *RSInputCreatePersonaSelection(NSString *scope);
#import "../Preferences/RSOptions.h"

static NSUserDefaults *RSAIPreferences(void) {
    static NSUserDefaults *prefs; static dispatch_once_t once;
    dispatch_once(&once, ^{ prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"]; });
    return prefs;
}
static NSMutableDictionary *RSAIKeyQuery(void) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:@"com.moxuan.regionshot.ai",
              (__bridge id)kSecAttrAccount:@"api-key"} mutableCopy];
}
NSString *RSAIReadKey(void) {
    NSString *shared = RSInputReadKey(); if (shared != nil) return shared;
    NSMutableDictionary *query = RSAIKeyQuery(); query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL; OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSData *data = CFBridgingRelease(result);
    return status == errSecSuccess ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}
OSStatus RSAIWriteKey(NSString *key) {
    NSMutableDictionary *query = RSAIKeyQuery();
    NSDictionary *value = @{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)value);
    if (status != errSecItemNotFound) return status;
    [query addEntriesFromDictionary:value]; return SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}

static NSArray<NSDictionary *> *RSAIDefaultPersonas(void) {
    return @[
        @{@"name":@"截图分析助手", @"scope":@"图片问答默认", @"builtin":@YES,
          @"prompt":@"你是看图分析工具。请识别图片中的文字、数据、图表与内容，并仅基于可见信息直接给出答案、总结或说明。无法确认的信息请明确标注“无法识别”或“不清晰”。不提问、不输出多余解释，仅输出最终结果。"},
        @{@"name":@"文字助手", @"scope":@"文字问答默认", @"builtin":@YES,
          @"prompt":@"你是文字处理助手。请准确理解用户提供的文字，直接完成总结、改写、解释或回答。信息不足时明确指出，不编造内容。"},
        @{@"name":@"AI 问答助手", @"scope":@"AI 问答默认", @"builtin":@YES,
          @"prompt":@"你是简洁、准确的 AI 问答助手。直接回答用户问题；无法确认的信息应明确说明。"}
    ];
}
NSArray<NSDictionary *> *RSAIPersonas(void) {
    id saved = [RSAIPreferences() objectForKey:@"AIPersonas"];
    NSArray *source = [saved isKindOfClass:NSArray.class] && [saved count] ? saved : RSAIDefaultPersonas();
    NSMutableArray *result = [NSMutableArray array]; NSInteger next = MAX(100, [RSAIPreferences() integerForKey:@"AINextPersonaMenuID"]);
    for (NSDictionary *p in source) next = MAX(next, [p[@"menuID"] integerValue] + 1);
    for (NSDictionary *p in source) {
        NSMutableDictionary *entry = p.mutableCopy;
        if (!entry[@"menuID"]) entry[@"menuID"] = @(next++);
        [result addObject:entry];
    }
    [RSAIPreferences() setInteger:next forKey:@"AINextPersonaMenuID"];
    [RSAIPreferences() setObject:result forKey:@"AIPersonas"];
    return result;
}
NSString *RSAIPersonaPrompt(BOOL imageQuestion) {
    NSString *scope = imageQuestion ? @"图片问答默认" : @"文字问答默认";
    for (NSDictionary *persona in RSAIPersonas()) if ([persona[@"scope"] isEqual:scope]) return persona[@"prompt"] ?: @"";
    return @"";
}

static BOOL RSPublishInputSettings(NSString *key) {
    NSUserDefaults *prefs = RSAIPreferences(); NSMutableArray *actions = [NSMutableArray array];
    for (NSDictionary *persona in RSAIPersonas()) [actions addObject:@{@"title":persona[@"name"] ?: @"AI", @"prompt":persona[@"prompt"] ?: @"", @"id":[persona[@"menuID"] description] ?: persona[@"name"]}];
    return RSInputSaveConfig(@{@"endpoint":[prefs stringForKey:@"AIEndpoint"] ?: @"", @"model":[prefs stringForKey:@"AIModel"] ?: @"", @"actions":actions, @"fastResponse":RSOption(@"AIFastResponse")}, key ?: RSAIReadKey() ?: @"");
}
@interface RSAIPersonaEditor : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextView *promptView;
@property (nonatomic, strong) UISegmentedControl *presentation;
@property (nonatomic, copy) NSDictionary *persona;
@property (nonatomic, copy) void (^saveHandler)(NSDictionary *persona);
@end
@implementation RSAIPersonaEditor
- (instancetype)initWithPersona:(NSDictionary *)persona save:(void (^)(NSDictionary *))save {
    if ((self = [super init])) { _persona = persona; _saveHandler = save; self.title = @"编辑人设"; } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.nameField = [UITextField new]; self.nameField.placeholder = @"名称"; self.nameField.text = self.persona[@"name"];
    self.nameField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.nameField.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.nameField.layer.cornerRadius = 18; self.nameField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 18, 1)]; self.nameField.leftViewMode = UITextFieldViewModeAlways;
    self.promptView = [UITextView new]; self.promptView.text = self.persona[@"prompt"]; self.promptView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.promptView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor; self.promptView.layer.cornerRadius = 18;
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO; self.promptView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.nameField]; [self.view addSubview:self.promptView];
    self.presentation = [[UISegmentedControl alloc] initWithItems:@[@"现有对话窗口", @"KeyboardAI 窗口"]];
    self.presentation.selectedSegmentIndex = [self.persona[@"presentation"] isEqual:@"keyboardai"] ? 1 : 0;
    self.presentation.accessibilityLabel = @"AI 回答展示方式";
    self.presentation.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.presentation];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[self.nameField.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.nameField.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16], [self.nameField.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [self.nameField.heightAnchor constraintEqualToConstant:72], [self.promptView.leadingAnchor constraintEqualToAnchor:self.nameField.leadingAnchor],
        [self.promptView.trailingAnchor constraintEqualToAnchor:self.nameField.trailingAnchor], [self.presentation.topAnchor constraintEqualToAnchor:self.nameField.bottomAnchor constant:12], [self.presentation.leadingAnchor constraintEqualToAnchor:self.nameField.leadingAnchor], [self.presentation.trailingAnchor constraintEqualToAnchor:self.nameField.trailingAnchor], [self.presentation.heightAnchor constraintEqualToConstant:40], [self.promptView.topAnchor constraintEqualToAnchor:self.presentation.bottomAnchor constant:12],
        [self.promptView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16]]];
}
- (void)save {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *prompt = [self.promptView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || !prompt.length || name.length > 100 || prompt.length > 8000) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法保存人设" message:@"名称需 1–100 字符，人设内容需 1–8,000 字符。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; return;
    }
    NSMutableDictionary *value = [self.persona mutableCopy] ?: [NSMutableDictionary dictionary];
    value[@"presentation"] = self.presentation.selectedSegmentIndex == 1 ? @"keyboardai" : @"chat";
    value[@"name"] = name; value[@"prompt"] = prompt; value[@"scope"] = value[@"scope"] ?: @"自定义人设"; value[@"builtin"] = value[@"builtin"] ?: @NO;
    if (self.saveHandler) self.saveHandler(value.copy); [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface RSAIPersonasController : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *personas;
@end
@implementation RSAIPersonasController
- (instancetype)init { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"人设"; return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.personas = [RSAIPersonas() mutableCopy];
    self.navigationItem.rightBarButtonItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)],
        [[UIBarButtonItem alloc] initWithTitle:@"恢复默认配置" style:UIBarButtonItemStylePlain target:self action:@selector(reset)]];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.personas.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NSDictionary *p = self.personas[path.row];
    cell.textLabel.text = p[@"name"]; cell.detailTextLabel.text = p[@"scope"]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { [tableView deselectRowAtIndexPath:path animated:YES]; [self edit:path.row]; }
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return ![self.personas[path.row][@"builtin"] boolValue]; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return; [self.personas removeObjectAtIndex:path.row]; [self persist]; [tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
}
- (void)add {
    __weak typeof(self) weakSelf = self;
    NSDictionary *persona = @{@"name":@"新建人设", @"prompt":@"", @"scope":@"自定义人设", @"builtin":@NO};
    RSAIPersonaEditor *editor = [[RSAIPersonaEditor alloc] initWithPersona:persona save:^(NSDictionary *value) {
        [weakSelf.personas addObject:value]; [weakSelf persist]; [weakSelf.tableView reloadData];
    }]; [self.navigationController pushViewController:editor animated:YES];
}
- (void)edit:(NSUInteger)index {
    __weak typeof(self) weakSelf = self; RSAIPersonaEditor *editor = [[RSAIPersonaEditor alloc] initWithPersona:self.personas[index] save:^(NSDictionary *value) {
        weakSelf.personas[index] = value; [weakSelf persist]; [weakSelf.tableView reloadData];
    }]; [self.navigationController pushViewController:editor animated:YES];
}
- (void)reset { self.personas = [RSAIDefaultPersonas() mutableCopy]; [self persist]; [self.tableView reloadData]; }
- (void)persist { [RSAIPreferences() setObject:self.personas.copy forKey:@"AIPersonas"]; [RSAIPreferences() synchronize]; self.personas = [RSAIPersonas() mutableCopy]; RSPublishInputSettings(nil); }
@end

@interface RSAIBallSettingsController : UITableViewController
@end
@implementation RSAIBallSettingsController
- (instancetype)init { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"AI 悬浮球设置"; return self; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [UITableViewCell new]; cell.textLabel.text = path.row ? @"透明度" : @"大小";
    UISlider *slider = [UISlider new]; slider.frame = CGRectMake(0, 0, 180, 32); slider.tag = path.row;
    slider.minimumValue = path.row ? 0.25 : 36; slider.maximumValue = path.row ? 1 : 80;
    slider.value = [RSOption(path.row ? @"AIBallOpacity" : @"AIBallSize") floatValue]; [slider addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = slider; return cell;
}
- (void)changed:(UISlider *)slider { RSSetOption(slider.tag ? @"AIBallOpacity" : @"AIBallSize", @(slider.value)); }
@end

@interface RSAIChoiceController : UITableViewController
@property (nonatomic, copy) NSArray<NSString *> *choices;
@property (nonatomic) NSInteger selected;
@property (nonatomic, copy) void (^choose)(NSInteger);
@end
@implementation RSAIChoiceController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.choices.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = self.choices[path.row]; cell.accessoryType = path.row == self.selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (self.choose) self.choose(path.row); if (self.navigationController.topViewController == self) [self.navigationController popViewControllerAnimated:YES];
}
@end
@interface RSAIValueController : UIViewController
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, copy) NSString *value;
@property (nonatomic) BOOL secret;
@property (nonatomic, copy) void (^commit)(NSString *);
@end
@implementation RSAIValueController
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(saveValue)];
    self.field = [UITextField new]; self.field.text = self.value; self.field.secureTextEntry = self.secret;
    self.field.borderStyle = UITextBorderStyleRoundedRect; self.field.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeNone; self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.accessibilityLabel = self.title; self.field.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.field];
    [NSLayoutConstraint activateConstraints:@[[self.field.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20], [self.field.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20], [self.field.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24], [self.field.heightAnchor constraintEqualToConstant:52]]];
}
- (void)saveValue { if (self.commit) self.commit([self.field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]); [self.navigationController popViewControllerAnimated:YES]; }
@end

@interface RSAISettingsController ()
@property (nonatomic, copy) dispatch_block_t saved;
@property (nonatomic, copy) NSString *endpoint;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, strong) NSArray<NSString *> *models;
@property (nonatomic) BOOL fetching;
@property (nonatomic, strong) UITableView *modelTable;
@end
@implementation RSAISettingsController
- (instancetype)initWithSaved:(dispatch_block_t)saved {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _saved = saved; self.title = @"AI 服务配置"; NSUserDefaults *prefs = RSAIPreferences();
        _endpoint = [prefs stringForKey:@"AIEndpoint"] ?: @"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";
        _model = [prefs stringForKey:@"AIModel"] ?: @"qwen-vl-max"; _key = RSAIReadKey();
        id models = [prefs objectForKey:@"AIModels"]; _models = [models isKindOfClass:NSArray.class] ? models : @[];
    } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    if (self.navigationController.viewControllers.firstObject == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回对话" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return tableView == self.modelTable ? 1 : 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.modelTable) return MAX(1, self.models.count);
    if (section == 0) return 1; if (section == 1) return 6; if (section == 2) return 1; return 4;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return tableView == self.modelTable ? nil : @[@"AI 引擎", @"服务配置", @"AI 人设", @"显示与输出"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (tableView == self.modelTable) return nil;
    if (section == 3) return @"快速响应对兼容的通义模型关闭深度思考，减少首字等待；复杂推理需要时可关闭。流式输出可逐字显示回答。";
    return section == 1 ? @"模型抓取使用兼容接口的 /v1/models；发送图片和文字时使用当前选中的模型。" : (section == 2 ? @"默认人设可修改配置，自定义人设可以添加或删除。" : nil);
}
- (UITableViewCell *)cell:(NSString *)title detail:(NSString *)detail disclosure:(BOOL)disclosure {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; cell.textLabel.text = title; cell.detailTextLabel.text = detail;
    cell.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone; return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return tableView != self.modelTable && path.section == 1 && path.row == 3 ? 180 : 48; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (tableView == self.modelTable) {
        NSString *model = self.models.count ? self.models[path.row] : @"点击下方“模型抓取”加载列表";
        UITableViewCell *cell = [self cell:model detail:nil disclosure:NO]; cell.backgroundColor = UIColor.clearColor;
        cell.accessoryType = [model isEqual:self.model] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; return cell;
    }
    if (path.section == 0) return [self cell:@"当前使用的引擎" detail:[self.endpoint containsString:@"dashscope"] ? @"通义千问" : @"兼容服务" disclosure:YES];
    if (path.section == 1) {
        if (path.row == 0) return [self cell:@"API Key" detail:self.key.length ? @"已设置" : @"未设置" disclosure:YES];
        if (path.row == 1) return [self cell:@"服务地址" detail:self.endpoint disclosure:YES];
        if (path.row == 2) return [self cell:@"当前模型" detail:self.model disclosure:YES];
        if (path.row == 4) return [self cell:self.fetching ? @"正在抓取模型…" : @"模型抓取" detail:nil disclosure:NO];
        if (path.row == 5) return [self cell:@"打开获取 API 网址" detail:nil disclosure:NO];
        UITableViewCell *cell = [self cell:@"" detail:nil disclosure:NO]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!self.modelTable) { self.modelTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; self.modelTable.dataSource = self; self.modelTable.delegate = self; self.modelTable.separatorStyle = UITableViewCellSeparatorStyleNone; self.modelTable.backgroundColor = UIColor.tertiarySystemFillColor; self.modelTable.layer.cornerRadius = 18; self.modelTable.clipsToBounds = YES; }
        [self.modelTable removeFromSuperview]; self.modelTable.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:self.modelTable];
        [NSLayoutConstraint activateConstraints:@[[self.modelTable.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12], [self.modelTable.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12], [self.modelTable.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8], [self.modelTable.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8]]];
        [self.modelTable reloadData]; return cell;
    }
    if (path.section == 2) return [self cell:@"人设" detail:[NSString stringWithFormat:@"%lu 个", (unsigned long)RSAIPersonas().count] disclosure:YES];
    if (path.row == 0) return [self cell:@"AI 悬浮球设置" detail:nil disclosure:YES];
    if (path.row == 1) return [self cell:@"AI 窗口主题" detail:@[@"跟随系统", @"浅色", @"深色"][MIN(2, [RSOption(@"AITheme") integerValue])] disclosure:YES];
    if (path.row == 3) { UITableViewCell *cell = [self cell:@"快速响应" detail:nil disclosure:NO]; UISwitch *toggle = [UISwitch new]; toggle.on = [RSOption(@"AIFastResponse") boolValue]; [toggle addTarget:self action:@selector(fastResponse:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; return cell; }
    UITableViewCell *cell = [self cell:@"流式输出" detail:nil disclosure:NO]; UISwitch *toggle = [UISwitch new]; toggle.on = [RSOption(@"AIStream") boolValue]; [toggle addTarget:self action:@selector(stream:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (tableView == self.modelTable) { if (self.models.count) self.model = self.models[path.row]; [self.tableView reloadData]; return; }
    if (path.section == 0) { [self chooseEngine:path]; return; }
    if (path.section == 1) {
        if (path.row <= 2) { [self editValue:path.row]; return; }
        if (path.row == 4) { [self fetchModels]; return; }
        if (path.row == 5) { [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://bailian.console.aliyun.com/"] options:@{} completionHandler:nil]; return; }
        return;
    }
    if (path.section == 2) { [self.navigationController pushViewController:[RSAIPersonasController new] animated:YES]; return; }
    if (path.row == 0) { [self.navigationController pushViewController:[RSAIBallSettingsController new] animated:YES]; return; }
    if (path.row == 1) [self chooseTheme:path];
}
- (void)chooseEngine:(NSIndexPath *)path {
    RSAIChoiceController *page = [RSAIChoiceController new]; page.title = @"AI 引擎"; page.choices = @[@"通义千问", @"自定义兼容服务"]; page.selected = [self.endpoint containsString:@"dashscope"] ? 0 : 1;
    __weak typeof(self) weakSelf = self;
    page.choose = ^(NSInteger value) { if (value == 0) weakSelf.endpoint = @"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"; else [weakSelf editValue:1]; };
    [self.navigationController pushViewController:page animated:YES];
}
- (void)editValue:(NSInteger)row {
    RSAIValueController *page = [RSAIValueController new]; page.title = @[@"API Key", @"服务地址", @"模型名称"][row]; page.value = @[self.key ?: @"", self.endpoint ?: @"", self.model ?: @""][row]; page.secret = row == 0;
    __weak typeof(self) weakSelf = self;
    page.commit = ^(NSString *value) { if (row == 0) weakSelf.key = value; else if (row == 1) weakSelf.endpoint = value; else weakSelf.model = value; };
    [self.navigationController pushViewController:page animated:YES];
}
- (NSURL *)modelsURL {
    NSURLComponents *parts = [NSURLComponents componentsWithString:self.endpoint]; if (![parts.scheme.lowercaseString isEqual:@"https"] || !parts.host.length || parts.user || parts.password) return nil;
    NSArray *segments = [parts.path componentsSeparatedByString:@"/"]; NSUInteger index = [segments indexOfObject:@"chat"];
    if (index != NSNotFound) parts.path = [[[segments subarrayWithRange:NSMakeRange(0, index)] componentsJoinedByString:@"/"] stringByAppendingString:@"/models"];
    else parts.path = [[parts.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"models"];
    parts.query = nil; parts.fragment = nil; return parts.URL;
}
- (void)fetchModels {
    if (self.fetching) return; NSURL *url = [self modelsURL]; if (!url) { [self show:@"请先填写有效的 HTTPS 服务地址。"]; return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url]; request.timeoutInterval = 30; if (self.key.length) [request setValue:[@"Bearer " stringByAppendingString:self.key] forHTTPHeaderField:@"Authorization"];
    self.fetching = YES; [self.tableView reloadData];
    [[[NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id json = data.length <= 2 * 1024 * 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil; id rows = [json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil; NSMutableArray *models = [NSMutableArray array];
        if ([rows isKindOfClass:NSArray.class]) for (id item in rows) { NSString *name = [item isKindOfClass:NSDictionary.class] ? item[@"id"] : nil; if ([name isKindOfClass:NSString.class] && name.length) [models addObject:name]; }
        dispatch_async(dispatch_get_main_queue(), ^{ self.fetching = NO; if (models.count) { self.models = models.copy; if (!self.model.length) self.model = models.firstObject; [self.tableView reloadData]; } else [self show:error.localizedDescription ?: @"没有获取到可用模型，请检查地址、密钥与网络。"];
        });
    }] resume];
}
- (void)chooseTheme:(NSIndexPath *)path {
    RSAIChoiceController *page = [RSAIChoiceController new]; page.title = @"AI 窗口主题"; page.choices = @[@"跟随系统", @"浅色", @"深色"]; page.selected = [RSOption(@"AITheme") integerValue];
    page.choose = ^(NSInteger value) { RSSetOption(@"AITheme", @(value)); };
    [self.navigationController pushViewController:page animated:YES];
}
- (void)fastResponse:(UISwitch *)toggle { RSSetOption(@"AIFastResponse", @(toggle.on)); }
- (void)stream:(UISwitch *)toggle { RSSetOption(@"AIStream", @(toggle.on)); }
- (void)show:(NSString *)message { UIAlertController *a = [UIAlertController alertControllerWithTitle:@"AI 问答" message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)save {
    NSURL *url = [NSURL URLWithString:self.endpoint]; if (![url.scheme.lowercaseString isEqual:@"https"] || !url.host.length || url.user || url.password || !self.model.length) { [self show:@"请填写有效的 HTTPS 服务地址和模型名称。"]; return; }
    OSStatus status = RSAIWriteKey(self.key ?: @""); if (status != errSecSuccess) { [self show:[NSString stringWithFormat:@"钥匙串保存失败（%d）。", (int)status]]; return; }
    NSUserDefaults *prefs = RSAIPreferences(); [prefs setObject:self.endpoint forKey:@"AIEndpoint"]; [prefs setObject:self.model forKey:@"AIModel"]; [prefs setObject:self.models forKey:@"AIModels"]; [prefs synchronize];
    if (!RSPublishInputSettings(self.key)) { [self show:@"AI 配置已保存，但微信、LINE 共享配置写入失败，请检查权限后重试。"]; return; }
    if (self.navigationController.viewControllers.firstObject != self) [self.navigationController popViewControllerAnimated:YES]; else if (self.navigationController.parentViewController) { if (self.saved) self.saved(); } else [self dismissViewControllerAnimated:YES completion:self.saved];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@implementation RSAIMenuController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"AI 对话与设置"; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? 5 : 3; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"AI 对话" : @"各入口显示的人设"; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = path.section == 0 ? @[@"打开 AI 对话", @"对话外观与行为", @"AI 服务配置", @"AI 人设", @"Sileo 介绍页翻译"][path.row] : @[@"微信菜单", @"LINE 菜单", @"分词按钮长按菜单"][path.row];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    UIViewController *page = nil;
    if (path.section == 1) page = RSInputCreatePersonaSelection(@[@"wechatHiddenPersonas", @"lineHiddenPersonas", @"clipboardHiddenPersonas"][path.row]);
    else if (path.row == 0) { notify_post("com.moxuan.regionshot/AIWindow"); return; }
    else if (path.row == 1) { RSBehaviorSettings *options = [RSBehaviorSettings new]; options.groupIndex = RSOptionGroups().count - 1; page = options; }
    else if (path.row == 2) page = [[RSAISettingsController alloc] initWithSaved:nil];
    else if (path.row == 3) page = [RSAIPersonasController new];
    else page = RSCreateSileoSettings();
    [self.navigationController pushViewController:page animated:YES];
}
@end
