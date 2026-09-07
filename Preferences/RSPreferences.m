#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Selection/RSMenuSettings.h"
#import "../Capture/RSCaptureStatus.h"
#import "RSBehaviorSettings.h"
@interface RSPreferences : PSListController
@property (nonatomic, strong) PSSpecifier *diagnosticGroup;
@property (nonatomic) BOOL diagnosticPending;
@end
@implementation RSPreferences
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"RegionShot 0.3.2"];
    [group setProperty:@"侧边键 + 音量加进入区域截图。安装后需重新启动 SpringBoard。关闭开关恢复系统截图。" forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用区域截图" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:@"Enabled" forKey:@"key"]; [enabled setProperty:@YES forKey:@"default"];
    [items addObject:enabled];
    PSSpecifier *menu = [PSSpecifier preferenceSpecifierNamed:@"工具条与自定义图标" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    menu.buttonAction = @selector(openMenu); [items addObject:menu];
    PSSpecifier *options = [PSSpecifier preferenceSpecifierNamed:@"截图、浮图、OCR、长图与 AI 设置" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    options.buttonAction = @selector(openOptions); [items addObject:options];
    PSSpecifier *ai = [PSSpecifier preferenceSpecifierNamed:@"配置 AI 服务、模型与密钥" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    ai.buttonAction = @selector(openAI); [items addObject:ai];
    PSSpecifier *test = [PSSpecifier preferenceSpecifierNamed:@"测试截图入口" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    test.buttonAction = @selector(testCapture); [items addObject:test];
    PSSpecifier *check = [PSSpecifier preferenceSpecifierNamed:@"检查 SpringBoard 状态" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    check.buttonAction = @selector(checkCapture); [items addObject:check];
    self.diagnosticGroup = [PSSpecifier groupSpecifierWithName:@"设备诊断"];
    [self.diagnosticGroup setProperty:@"尚未检查。点击上方按钮可检查插件加载、截图接口和按键入口。" forKey:@"footerText"];
    [items addObject:self.diagnosticGroup];
    group = [PSSpecifier groupSpecifierWithName:@"当前开发预览"];
    [group setProperty:@"支持工具条排序、显示、名称、图片/SF Symbol 图标和大小。AI 服务仍在图片问答窗口标题处配置。完整设置、自动上滑长截图及其他功能仍在开发中。" forKey:@"footerText"];
    [items addObject:group]; _specifiers = items.copy; return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"];
    [prefs synchronize];
    return [prefs objectForKey:[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"];
    [prefs setObject:value forKey:[specifier propertyForKey:@"key"]]; [prefs synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.moxuan.regionshot/ReloadPrefs"), NULL, NULL, YES);
}
- (void)openMenu { [self.navigationController pushViewController:[RSMenuSettings new] animated:YES]; }
- (void)openOptions { [self.navigationController pushViewController:[RSBehaviorSettings new] animated:YES]; }
- (void)openAI { notify_post("com.moxuan.regionshot/AISettings"); }
- (void)testCapture { [self diagnoseCapture:YES]; }
- (void)checkCapture { [self diagnoseCapture:NO]; }
- (void)showDiagnostic:(NSString *)message {
    [self.diagnosticGroup setProperty:message forKey:@"footerText"];
    [self reloadSpecifier:self.diagnosticGroup];
}
- (void)diagnoseCapture:(BOOL)launch {
    if (self.diagnosticPending) return;
    int requestToken = -1, responseToken = -1;
    if (notify_register_check(RS_CAPTURE_CHECK, &requestToken) != NOTIFY_STATUS_OK ||
        notify_register_check(RS_CAPTURE_STATUS, &responseToken) != NOTIFY_STATUS_OK) {
        if (requestToken >= 0) notify_cancel(requestToken);
        if (responseToken >= 0) notify_cancel(responseToken);
        [self showDiagnostic:@"无法注册系统通知，尚未发送截图请求。"];
        return;
    }
    // A fresh request ID prevents a previous process or button press from passing this check.
    uint64_t nonce = (uint64_t)(arc4random_uniform(UINT32_MAX - 1) + 1) << 32;
    if (notify_set_state(requestToken, nonce | (launch ? 1 : 0)) != NOTIFY_STATUS_OK ||
        notify_post(RS_CAPTURE_CHECK) != NOTIFY_STATUS_OK) {
        notify_cancel(requestToken); notify_cancel(responseToken);
        [self showDiagnostic:@"系统通知发送失败，尚未确认截图请求。"];
        return;
    }
    self.diagnosticPending = YES;
    [self showDiagnostic:@"正在等待 SpringBoard 响应…"];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        uint64_t response = 0;
        BOOL received = notify_get_state(responseToken, &response) == NOTIFY_STATUS_OK &&
                        (response & UINT64_C(0xffffffff00000000)) == nonce;
        notify_cancel(requestToken); notify_cancel(responseToken);
        RSPreferences *controller = weakSelf;
        if (!controller) return;
        controller.diagnosticPending = NO;
        uint32_t status = (uint32_t)response;
        NSString *message;
        if (!received) {
            message = @"SpringBoard 在 3 秒内未响应。请确认安装的是 0.3.2、已重新启动 SpringBoard，并检查 RootHide 注入管理器是否允许 RegionShot 注入 SpringBoard。此状态尚不能确认插件已加载。";
        } else {
            NSString *result = !launch ? @"状态检查完成。" : (status & RSStatusStarted) ? @"截图请求已接受并建立选区窗口；请确认屏幕上实际可见。" : @"区域截图启动失败。";
            message = [NSString stringWithFormat:@"SpringBoard 已响应。\n插件开关：%@\n截图接口：%@\n入口：按键 %@ / 应用 %@ / 编辑 %@ / 捕获器 %@\n%@",
                status & RSStatusEnabled ? @"开启" : @"关闭",
                status & RSStatusSymbol ? @"可用" : @"未找到",
                status & RSStatusHardware ? @"已挂接" : @"不可用",
                status & RSStatusApplication ? @"已挂接" : @"不可用",
                status & RSStatusEdit ? @"已挂接" : @"不可用",
                status & RSStatusCapturer ? @"已挂接" : @"不可用", result];
        }
        [controller showDiagnostic:message];
        if (launch && (!received || !(status & RSStatusStarted)) && controller.view.window && !controller.presentedViewController) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"区域截图未启动" message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [controller presentViewController:alert animated:YES completion:nil];
        }
    });
}
@end
