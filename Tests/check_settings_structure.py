"""Guard the settings-only reorganization against configuration changes."""
import json, re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = (root / 'Preferences/RSOptions.m').read_text(encoding='utf-8')
actual = {}
for line in source.splitlines():
    match = re.search(r'@"key":@"([^"]+)"', line)
    if match:
        actual[match[1]] = dict(re.findall(r'@"(key|default|min|max|limit)":(@"(?:[^"\\]|\\.)*"|@[-\w.]+)', line))
assert actual == json.loads((root / 'Tests/settings_contract.json').read_text(encoding='utf-8'))
page = (root / 'Preferences/RSPreferences.m').read_text(encoding='utf-8')
for selector in re.findall(r'@"((?:open|test|check)\w+)"', page):
    assert re.search(r'- \(void\)' + selector + r'\b', page), selector
assert '当前开发预览' not in page and '关于' not in page
assert page.index('@"Enabled"') < page.index('NSArray *sections')
assert 'presentViewController:self.pages' not in page
behavior = (root / 'Preferences/RSBehaviorSettings.m').read_text(encoding='utf-8')
controller = (root / 'LongShot/RSLongCaptureController.m').read_text(encoding='utf-8')
header = (root / 'LongShot/RSLongCaptureController.h').read_text(encoding='utf-8')
makefile = (root / 'Makefile').read_text(encoding='utf-8')
injection = (root / 'RegionShot.plist').read_text(encoding='utf-8')
swipe = (root / 'LongShot/RSLongSwipe.m').read_text(encoding='utf-8')
assert '@"choiceValues":@[@2, @3]' in source
assert 'choiceValues.count > index ? choiceValues[index] : @(index)' in behavior
assert '[value unsignedIntegerValue]' not in behavior
ai_settings = (root / 'AI/RSAISettingsController.m').read_text(encoding='utf-8')
chat = (root / 'AI/RSChatController.m').read_text(encoding='utf-8')
assert '@"AIQuickPhrases"' in ai_settings and '@"短语"' in ai_settings
for action in ('choosePhoto:', 'chooseFile:', 'openCamera:', 'showPhrases:'):
    assert action in chat
assert 'RSAIQuickPhrases()' in chat
assert 'constraintEqualToConstant:260' in chat and 'MAX(220, size.height + 156' in chat
assert 'RSInstallMaterialBackground(button, 16)' in chat
assert 'bringSubviewToFront:button.imageView' in chat and 'bringSubviewToFront:button.titleLabel' in chat
assert '+ (void)minimizeForLock' in chat and 'AIMinimizeOnLock' in chat
assert '[RSChatController minimizeForLock]' in (root / 'Trigger.xm').read_text(encoding='utf-8')
assert 'RSAICreatePhrasesController()' in behavior
assert '@[@"打开对话", @"复制对话调用地址", @"对话设置", @"服务配置", @"人设", @"弹出式窗口"]' in ai_settings
assert 'prefs://root=regionshot_aiwindow' in ai_settings
camera = (root / 'AI/RSChatCameraController.m').read_text(encoding='utf-8')
assert '[self.output connectionWithMediaType:AVMediaTypeVideo]' in camera
assert '[self updateVideoOrientation];' in camera
assert 'RSActiveOrientation(self.host.windowScene)' in camera
assert 'name:@"com.moxuan.regionshot.orientation.target"' in camera
assert '[NSNotificationCenter.defaultCenter removeObserver:self]' in camera
assert 'UIInterfaceOrientationLandscapeLeft) videoOrientation = AVCaptureVideoOrientationLandscapeLeft' in camera
assert 'UIInterfaceOrientationLandscapeRight) videoOrientation = AVCaptureVideoOrientationLandscapeRight' in camera
mode_block = re.search(r'typedef NS_ENUM\(NSInteger, RSLongCaptureMode\) \{([^}]+)\}', header).group(1)
assert set(re.findall(r'(RSLongCaptureMode\w+)\s*=', mode_block)) == {
    'RSLongCaptureModeManual', 'RSLongCaptureModeButtonStep'}
assert 'mode == RSLongCaptureModeButtonStep ? RSLongCaptureModeButtonStep : RSLongCaptureModeManual' in controller
assert '@"继续" action:@selector(continuePressed)' in controller
assert 'self.mode == RSLongCaptureModeButtonStep || self.stopped' in controller
assert 'LongShot/RSLongSwipe.m' in makefile
assert 'com.apple.UIKit' not in injection
assert 'progress * progress * (3.0 - 2.0 * progress)' in swipe
assert '700 * NSEC_PER_MSEC' in swipe
assert 'self.nextStepAllowedTime = now + 1.8' in controller
assert '- (void)enableContinueWhenReady' in controller
print('Verified original preference keys/defaults/ranges and root settings destinations')
