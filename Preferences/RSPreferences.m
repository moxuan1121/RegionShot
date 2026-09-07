#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Selection/RSMenuSettings.h"
@interface RSPreferences : PSListController
@end
@implementation RSPreferences
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"RegionShot 0.3.1"];
    [group setProperty:@"侧边键 + 音量加进入区域截图。安装后需重新启动 SpringBoard。关闭开关恢复系统截图。" forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用区域截图" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:@"Enabled" forKey:@"key"]; [enabled setProperty:@YES forKey:@"default"];
    [items addObject:enabled];
    PSSpecifier *menu = [PSSpecifier preferenceSpecifierNamed:@"工具条与自定义图标" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    menu.buttonAction = @selector(openMenu); [items addObject:menu];
    PSSpecifier *test = [PSSpecifier preferenceSpecifierNamed:@"测试截图入口" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    test.buttonAction = @selector(testCapture); [items addObject:test];
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
- (void)testCapture {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.moxuan.regionshot/TakeScreenshot"), NULL, NULL, YES);
}
@end
