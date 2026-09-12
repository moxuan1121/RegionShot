#import "../Preferences/RSSliderInput.h"
#import "../Input/RSInputStore.h"
#import "RSAISettingsController.h"
#import "../Preferences/RSBehaviorSettings.h"
#import <notify.h>
extern UIViewController *RSCreateSileoSettings(void);
extern UIViewController *RSInputCreateAIOptions(void);
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
NSArray<NSDictionary *> *RSAIQuickPhrases(void) {
    id saved = [RSAIPreferences() objectForKey:@"AIQuickPhrases"];
    if (![saved isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (id item in saved) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *title = item[@"name"], *prompt = item[@"prompt"];
        if ([title isKindOfClass:NSString.class] && title.length && [prompt isKindOfClass:NSString.class] && prompt.length)
            [result addObject:@{@"name":title, @"prompt":prompt}];
    }
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
@property (nonatomic) BOOL phrase;
@property (nonatomic, copy) void (^saveHandler)(NSDictionary *persona);
@end
@implementation RSAIPersonaEditor
- (instancetype)initWithPersona:(NSDictionary *)persona save:(void (^)(NSDictionary *))save {
    if ((self = [super init])) { _persona = persona; _saveHandler = save; self.title = @"编辑人设"; } return self;
}
- (instancetype)initWithPhrase:(NSDictionary *)phrase save:(void (^)(NSDictionary *))save {
    if ((self = [super init])) { _persona = phrase; _saveHandler = save; _phrase = YES; self.title = @"编辑短语"; } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.nameField = [UITextField new]; self.nameField.placeholder = self.phrase ? @"标题" : @"名称"; self.nameField.text = self.persona[@"name"];
    self.nameField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.nameField.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.nameField.layer.cornerRadius = 18; self.nameField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 18, 1)]; self.nameField.leftViewMode = UITextFieldViewModeAlways;
    self.promptView = [UITextView new]; self.promptView.text = self.persona[@"prompt"]; self.promptView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.promptView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor; self.promptView.layer.cornerRadius = 18;
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO; self.promptView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.nameField]; [self.view addSubview:self.promptView];
    if (!self.phrase) {
        self.presentation = [[UISegmentedControl alloc] initWithItems:@[@"对话式窗口", @"弹出式窗口"]];
        self.presentation.selectedSegmentIndex = [self.persona[@"presentation"] isEqual:@"keyboardai"] ? 1 : 0;
        self.presentation.accessibilityLabel = @"AI 回答展示方式";
        self.presentation.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.presentation];
    }
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutAnchor *promptTop = self.phrase ? self.nameField.bottomAnchor : self.presentation.bottomAnchor;
    [NSLayoutConstraint activateConstraints:@[[self.nameField.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.nameField.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16], [self.nameField.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [self.nameField.heightAnchor constraintEqualToConstant:72], [self.promptView.leadingAnchor constraintEqualToAnchor:self.nameField.leadingAnchor],
        [self.promptView.trailingAnchor constraintEqualToAnchor:self.nameField.trailingAnchor], [self.promptView.topAnchor constraintEqualToAnchor:promptTop constant:12],
        [self.promptView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16]]];
    if (self.presentation) [NSLayoutConstraint activateConstraints:@[[self.presentation.topAnchor constraintEqualToAnchor:self.nameField.bottomAnchor constant:12], [self.presentation.leadingAnchor constraintEqualToAnchor:self.nameField.leadingAnchor], [self.presentation.trailingAnchor constraintEqualToAnchor:self.nameField.trailingAnchor], [self.presentation.heightAnchor constraintEqualToConstant:40]]];
}
- (void)save {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *prompt = [self.promptView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || !prompt.length || name.length > 100 || prompt.length > 8000) {
        NSString *kind = self.phrase ? @"短语" : @"人设";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:[@"无法保存" stringByAppendingString:kind] message:self.phrase ? @"标题需 1–100 字符，提示语需 1–8,000 字符。" : @"名称需 1–100 字符，人设内容需 1–8,000 字符。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; return;
    }
    NSMutableDictionary *value = [self.persona mutableCopy] ?: [NSMutableDictionary dictionary];
    if (!self.phrase) value[@"presentation"] = self.presentation.selectedSegmentIndex == 1 ? @"keyboardai" : @"chat";
    value[@"name"] = name; value[@"prompt"] = prompt;
    if (!self.phrase) { value[@"scope"] = value[@"scope"] ?: @"自定义人设"; value[@"builtin"] = value[@"builtin"] ?: @NO; }
    if (self.saveHandler) self.saveHandler(value.copy); [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface RSAIPhrasesController : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *phrases;
@end
@implementation RSAIPhrasesController
- (instancetype)init { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"短语"; return self; }
- (void)viewDidLoad { [super viewDidLoad]; self.phrases = [RSAIQuickPhrases() mutableCopy]; self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.phrases.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.textLabel.text = self.phrases[path.row][@"name"]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { [tableView deselectRowAtIndexPath:path animated:YES]; [self edit:path.row]; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path { if (style != UITableViewCellEditingStyleDelete) return; [self.phrases removeObjectAtIndex:path.row]; [self persist]; [tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic]; }
- (void)add { __weak typeof(self) weakSelf = self; RSAIPersonaEditor *editor = [[RSAIPersonaEditor alloc] initWithPhrase:@{@"name":@"新建短语", @"prompt":@""} save:^(NSDictionary *value) { [weakSelf.phrases addObject:value]; [weakSelf persist]; [weakSelf.tableView reloadData]; }]; [self.navigationController pushViewController:editor animated:YES]; }
- (void)edit:(NSUInteger)index { __weak typeof(self) weakSelf = self; RSAIPersonaEditor *editor = [[RSAIPersonaEditor alloc] initWithPhrase:self.phrases[index] save:^(NSDictionary *value) { weakSelf.phrases[index] = value; [weakSelf persist]; [weakSelf.tableView reloadData]; }]; [self.navigationController pushViewController:editor animated:YES]; }
- (void)persist { [RSAIPreferences() setObject:self.phrases.copy forKey:@"AIQuickPhrases"]; [RSAIPreferences() synchronize]; }
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
@property (nonatomic, strong) NSURLSession *modelSession;
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
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.modelSession invalidateAndCancel];
    self.modelSession = nil; self.fetching = NO;
}
- (void)dealloc { [_modelSession invalidateAndCancel]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return tableView == self.modelTable ? 1 : 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.modelTable) return MAX(1, self.models.count);
    return section == 0 ? 1 : 6;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return tableView == self.modelTable ? nil : @[@"服务类型", @"连接与模型"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (tableView == self.modelTable) return nil;
    return section == 1 ? @"获取模型使用兼容接口的 /v1/models。保存后，图片和文字将发送到此服务。" : nil;
}
- (UITableViewCell *)cell:(NSString *)title detail:(NSString *)detail disclosure:(BOOL)disclosure {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; cell.textLabel.text = title; cell.detailTextLabel.text = detail;
    cell.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone; return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return tableView != self.modelTable && path.section == 1 && path.row == 3 ? 180 : 48; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (tableView == self.modelTable) {
        NSString *model = self.models.count ? self.models[path.row] : @"点击下方“获取模型”加载列表";
        UITableViewCell *cell = [self cell:model detail:nil disclosure:NO]; cell.backgroundColor = UIColor.clearColor;
        cell.accessoryType = [model isEqual:self.model] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; return cell;
    }
    if (path.section == 0) return [self cell:@"服务类型" detail:[self.endpoint containsString:@"dashscope"] ? @"通义千问" : @"兼容服务" disclosure:YES];
    if (path.section == 1) {
        if (path.row == 0) return [self cell:@"API Key" detail:self.key.length ? @"已设置" : @"未设置" disclosure:YES];
        if (path.row == 1) return [self cell:@"服务地址" detail:self.endpoint disclosure:YES];
        if (path.row == 2) return [self cell:@"当前模型" detail:self.model disclosure:YES];
        if (path.row == 4) return [self cell:self.fetching ? @"正在抓取模型…" : @"获取模型" detail:nil disclosure:NO];
        if (path.row == 5) return [self cell:@"打开服务控制台" detail:nil disclosure:NO];
        UITableViewCell *cell = [self cell:@"" detail:nil disclosure:NO]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!self.modelTable) { self.modelTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; self.modelTable.dataSource = self; self.modelTable.delegate = self; self.modelTable.separatorStyle = UITableViewCellSeparatorStyleNone; self.modelTable.backgroundColor = UIColor.tertiarySystemFillColor; self.modelTable.layer.cornerRadius = 18; self.modelTable.clipsToBounds = YES; }
        [self.modelTable removeFromSuperview]; self.modelTable.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:self.modelTable];
        [NSLayoutConstraint activateConstraints:@[[self.modelTable.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12], [self.modelTable.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12], [self.modelTable.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8], [self.modelTable.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8]]];
        [self.modelTable reloadData]; return cell;
    }
    return [self cell:@"" detail:nil disclosure:NO];
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
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    self.modelSession = session;
    __weak typeof(self) weakSelf = self;
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id json = data.length && data.length <= 2 * 1024 * 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil; id rows = [json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil; NSMutableArray *models = [NSMutableArray array];
        if ([rows isKindOfClass:NSArray.class]) for (id item in rows) { NSString *name = [item isKindOfClass:NSDictionary.class] ? item[@"id"] : nil; if ([name isKindOfClass:NSString.class] && name.length) [models addObject:name]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            RSAISettingsController *controller = weakSelf;
            if (!controller || controller.modelSession != session) return;
            controller.modelSession = nil; controller.fetching = NO;
            if (models.count) { controller.models = models.copy; if (!controller.model.length) controller.model = models.firstObject; [controller.tableView reloadData]; }
            else [controller show:error.localizedDescription ?: @"没有获取到可用模型，请检查地址、密钥与网络。"];
        });
    }] resume];
    [session finishTasksAndInvalidate];
}
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
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"AI"; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? 6 : 4; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"AI 对话" : @"各入口显示的人设"; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = path.section == 0 ? @[@"打开对话", @"对话设置", @"服务配置", @"人设", @"短语", @"弹出式窗口"][path.row] : @[@"微信菜单", @"LINE 菜单", @"分词按钮长按菜单", @"Sileo 介绍页翻译"][path.row];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    UIViewController *page = nil;
    if (path.section == 1 && path.row == 3) page = RSCreateSileoSettings();
    else if (path.section == 1) page = RSInputCreatePersonaSelection(@[@"wechatHiddenPersonas", @"lineHiddenPersonas", @"clipboardHiddenPersonas"][path.row]);
    else if (path.row == 0) { notify_post("com.moxuan.regionshot/AIWindow"); return; }
    else if (path.row == 1) { RSBehaviorSettings *options = [RSBehaviorSettings new]; options.groupIndex = RSOptionGroups().count - 1; page = options; }
    else if (path.row == 2) page = [[RSAISettingsController alloc] initWithSaved:nil];
    else if (path.row == 3) page = [RSAIPersonasController new];
    else if (path.row == 4) page = [RSAIPhrasesController new];
    else if (path.row == 5) page = RSInputCreateAIOptions();
    else page = RSCreateSileoSettings();
    [self.navigationController pushViewController:page animated:YES];
}
@end
