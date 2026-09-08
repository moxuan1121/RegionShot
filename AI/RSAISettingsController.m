#import "RSAISettingsController.h"
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
    if (!name.length || !prompt.length) return;
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
- (void)persist { [RSAIPreferences() setObject:self.personas.copy forKey:@"AIPersonas"]; [RSAIPreferences() synchronize]; }
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

@interface RSAISettingsController ()
@property (nonatomic, copy) dispatch_block_t saved;
@property (nonatomic, copy) NSString *endpoint;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, strong) NSArray<NSString *> *models;
@property (nonatomic) BOOL fetching;
@end
@implementation RSAISettingsController
- (instancetype)initWithSaved:(dispatch_block_t)saved {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _saved = saved; self.title = @"AI 问答"; NSUserDefaults *prefs = RSAIPreferences();
        _endpoint = [prefs stringForKey:@"AIEndpoint"] ?: @"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";
        _model = [prefs stringForKey:@"AIModel"] ?: @"qwen-vl-max"; _key = RSAIReadKey();
        id models = [prefs objectForKey:@"AIModels"]; _models = [models isKindOfClass:NSArray.class] ? models : @[];
    } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"确认" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; if (section == 1) return 5 + self.models.count; if (section == 2) return 1; return 4;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"AI 引擎", @"通义千问", @"AI 人设", @"显示与输出"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 3) return @"快速响应对兼容的通义模型关闭深度思考，减少首字等待；复杂推理需要时可关闭。流式输出可逐字显示回答。";
    return section == 1 ? @"模型抓取使用兼容接口的 /v1/models；发送图片和文字时使用当前选中的模型。" : (section == 2 ? @"默认人设可修改配置，自定义人设可以添加或删除。" : nil);
}
- (UITableViewCell *)cell:(NSString *)title detail:(NSString *)detail disclosure:(BOOL)disclosure {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; cell.textLabel.text = title; cell.detailTextLabel.text = detail;
    cell.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone; return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) return [self cell:@"当前使用的引擎" detail:[self.endpoint containsString:@"dashscope"] ? @"通义千问" : @"兼容服务" disclosure:YES];
    if (path.section == 1) {
        if (path.row == 0) return [self cell:@"API Key" detail:self.key.length ? @"已设置" : @"未设置" disclosure:YES];
        if (path.row == 1) return [self cell:@"服务地址" detail:self.endpoint disclosure:YES];
        if (path.row == 2) return [self cell:@"当前模型" detail:self.model disclosure:YES];
        if (path.row == 3) return [self cell:self.fetching ? @"正在抓取模型…" : @"模型抓取" detail:nil disclosure:NO];
        if (path.row == 4) return [self cell:@"打开获取 API 网址" detail:nil disclosure:NO];
        NSString *model = self.models[path.row - 5]; UITableViewCell *cell = [self cell:model detail:nil disclosure:NO]; cell.accessoryType = [model isEqual:self.model] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; return cell;
    }
    if (path.section == 2) return [self cell:@"人设" detail:[NSString stringWithFormat:@"%lu 个", (unsigned long)RSAIPersonas().count] disclosure:YES];
    if (path.row == 0) return [self cell:@"AI 悬浮球设置" detail:nil disclosure:YES];
    if (path.row == 1) return [self cell:@"AI 窗口主题" detail:@[@"跟随系统", @"浅色", @"深色"][MIN(2, [RSOption(@"AITheme") integerValue])] disclosure:YES];
    if (path.row == 3) { UITableViewCell *cell = [self cell:@"快速响应" detail:nil disclosure:NO]; UISwitch *toggle = [UISwitch new]; toggle.on = [RSOption(@"AIFastResponse") boolValue]; [toggle addTarget:self action:@selector(fastResponse:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; return cell; }
    UITableViewCell *cell = [self cell:@"流式输出" detail:nil disclosure:NO]; UISwitch *toggle = [UISwitch new]; toggle.on = [RSOption(@"AIStream") boolValue]; [toggle addTarget:self action:@selector(stream:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) { [self chooseEngine:path]; return; }
    if (path.section == 1) {
        if (path.row <= 2) { [self editValue:path.row]; return; }
        if (path.row == 3) { [self fetchModels]; return; }
        if (path.row == 4) { [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://bailian.console.aliyun.com/"] options:@{} completionHandler:nil]; return; }
        self.model = self.models[path.row - 5]; [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone]; return;
    }
    if (path.section == 2) { [self.navigationController pushViewController:[RSAIPersonasController new] animated:YES]; return; }
    if (path.row == 0) { [self.navigationController pushViewController:[RSAIBallSettingsController new] animated:YES]; return; }
    if (path.row == 1) [self chooseTheme:path];
}
- (void)chooseEngine:(NSIndexPath *)path {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"当前使用的引擎" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"通义千问" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { self.endpoint = @"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"; if (!self.model.length) self.model = @"qwen-vl-max"; [self.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"自定义兼容服务" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self editValue:1]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; sheet.popoverPresentationController.sourceView = self.tableView; sheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:path]; [self presentViewController:sheet animated:YES completion:nil];
}
- (void)editValue:(NSInteger)row {
    NSArray *titles = @[@"API Key", @"服务地址", @"模型名称"]; NSArray *values = @[self.key ?: @"", self.endpoint ?: @"", self.model ?: @""];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:titles[row] message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = values[row]; field.secureTextEntry = row == 0; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { NSString *v = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (row == 0) self.key = v; else if (row == 1) self.endpoint = v; else self.model = v; [self.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
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
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"AI 窗口主题" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger value = 0; value < 3; value++) { NSString *title = @[@"跟随系统", @"浅色", @"深色"][value]; [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { RSSetOption(@"AITheme", @(value)); [self.tableView reloadData]; }]]; }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; sheet.popoverPresentationController.sourceView = self.tableView; sheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:path]; [self presentViewController:sheet animated:YES completion:nil];
}
- (void)fastResponse:(UISwitch *)toggle { RSSetOption(@"AIFastResponse", @(toggle.on)); }
- (void)stream:(UISwitch *)toggle { RSSetOption(@"AIStream", @(toggle.on)); }
- (void)show:(NSString *)message { UIAlertController *a = [UIAlertController alertControllerWithTitle:@"AI 问答" message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)save {
    NSURL *url = [NSURL URLWithString:self.endpoint]; if (![url.scheme.lowercaseString isEqual:@"https"] || !url.host.length || url.user || url.password || !self.model.length) { [self show:@"请填写有效的 HTTPS 服务地址和模型名称。"]; return; }
    OSStatus status = RSAIWriteKey(self.key ?: @""); if (status != errSecSuccess) { [self show:[NSString stringWithFormat:@"钥匙串保存失败（%d）。", (int)status]]; return; }
    NSUserDefaults *prefs = RSAIPreferences(); [prefs setObject:self.endpoint forKey:@"AIEndpoint"]; [prefs setObject:self.model forKey:@"AIModel"]; [prefs setObject:self.models forKey:@"AIModels"]; [prefs synchronize];
    [self dismissViewControllerAnimated:YES completion:self.saved];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:self.saved]; }
@end
