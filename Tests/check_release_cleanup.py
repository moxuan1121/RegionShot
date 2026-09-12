"""Release-only hygiene; executable feature checks remain in the build workflow."""
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files'], cwd=root, text=True).splitlines()
for name in files:
    path = root / name
    if not path.exists() or path.suffix not in {'.m', '.h', '.xm'} or name.startswith('Tests/'):
        continue
    source = path.read_text(encoding='utf-8')
    assert not re.search(r'\b(?:NSLog|printf|os_log)\s*\(', source), name
    assert 'RS_CAPTURE_CHECK' not in source and 'RS_CAPTURE_STATUS' not in source, name

settings = (root / 'AI/RSAISettingsController.m').read_text(encoding='utf-8')
assert '[self.modelSession invalidateAndCancel]' in settings
assert 'controller.modelSession != session' in settings
assert '[session finishTasksAndInvalidate]' in settings
assert 'data.length && data.length <=' in settings
store = (root / 'Input/RSInputStore.m').read_text(encoding='utf-8')
assert '@finally { [file closeAndReturnError:NULL]; }' in store
trigger = (root / 'Trigger.xm').read_text(encoding='utf-8')
assert 'generation == RSNativeScreenshotGeneration' in trigger
capture = (root / 'Capture/RSScreenCapture.m').read_text(encoding='utf-8')
assert '_snapshotExcludingWindows:withRect:' not in capture
assert 'captureScreenExcludingWindows' not in capture
chat = (root / 'AI/RSChatController.m').read_text(encoding='utf-8')
assert '能否解析此文件取决于' not in chat
assert 'size.unsignedLongLongValue <= 64 * 1024 * 1024' in chat
assert 'data.length > 64 * 1024 * 1024' in chat
send = chat.split('- (void)send {', 1)[1].split('- (void)startRequest {', 1)[0]
assert send.index('[self startRequest]') < send.index('[self scrollToBottomAnimated:YES]')
composer = chat.split('UIStackView *composerActions', 1)[1].split('[content addArrangedSubview:composerActions]', 1)[0]
assert composer.index('@"照片"') < composer.index('@"文件"') < composer.index('@"相机"') < composer.index('@"短语"')
for name in ('Input/RSInputInterface.m', 'KeyboardAI/RSKAInterface.m'):
    panel = (root / name).read_text(encoding='utf-8')
    assert '[self observePanelEvents];' in panel
    close = panel.split('- (void)close {', 1)[1]
    assert '[NSNotificationCenter.defaultCenter removeObserver:self];' in close
print('Verified release hygiene, bounded model requests and stale callback guards')
floating = (root / 'Floating/RSFloatingWindow.m').read_text(encoding='utf-8')
assert 'controller.targetOrientation == orientation' in floating
assert 'controller.targetOrientation = orientation; controller.centerImages = YES' in floating
assert 'if (!self.centerImages) return' in floating and 'self.centerImages = NO' in floating
assert 'view.layer.opacity = 0' in floating and 'view.layer.opacity = 1' in floating
assert 'RSApplyWindowOrientation(self, orientation)' in floating
for name in ('Input/RSInputInterface.m', 'KeyboardAI/RSKAInterface.m'):
    source = (root / name).read_text(encoding='utf-8').split('- (void)showSearchMenu:', 1)[1]
    assert 'RSInputVisibleActions(@"clipboardHiddenPersonas")' in source
    assert '!self.tokenView ||' not in source
material = (root / 'Geometry/RSMaterialBackground.h').read_text(encoding='utf-8')
assert 'UIBlurEffectStyleSystemMaterial' in material
for name in ('Input/RSInputInterface.m', 'KeyboardAI/RSKAInterface.m',
             'AI/RSChatController.m', 'History/RSHistoryController.m'):
    assert 'RSInstallMaterialBackground' in (root / name).read_text(encoding='utf-8'), name
animation = (root / 'Geometry/RSWindowAnimation.h').read_text(encoding='utf-8')
assert 'backdrop.backgroundColor = UIColor.clearColor' in animation
assert 'backdrop.backgroundColor = backgroundColor' in animation
for name in ('AI/RSChatController.m', 'History/RSHistoryController.m'):
    assert 'RSOpenWindowSurfaceOverBackdrop' in (root / name).read_text(encoding='utf-8'), name
camera = (root / 'AI/RSChatCameraController.m').read_text(encoding='utf-8')
assert 'UIPinchGestureRecognizer' in camera and 'videoZoomFactor = zoom' in camera
assert 'RSInstallMaterialBackground(self.card, 20)' in camera
support = (root / 'CameraSupport/RSCameraMediaSupport.m').read_text(encoding='utf-8')
assert '(id, SEL, void *, id)' in support and support.count('MSHookMessageEx') == 1
assert 'RSLog' not in support
assert 'action:@selector(restoreFromBall)' in chat
assert '- (void)restoreFromBall { [self restoreFocusingInput:NO]; }' in chat
assert 'self.ball.backgroundColor = UIColor.systemBlueColor' in chat
assert 'bezierPathWithOvalInRect:self.ball.bounds' in chat
assert 'CGRectGetMaxX(safe) - radius - 16' not in chat
assert '+ (void)showCameraInScene:' in chat
assert 'com.moxuan.regionshot/AICamera' in trigger
external_camera = chat.split('+ (void)showCameraInScene:', 1)[1].split('- (void)showPhrases:', 1)[0]
assert external_camera.index('RSOpeningExternalCamera = YES') < external_camera.index('[self showImage:nil scene:scene]')
assert 'RSChatCameraController.isVisible' in chat.split('- (void)focusInput', 1)[1].split('- (void)updateHeading', 1)[0]
camera_action = chat.split('- (void)openCamera:', 1)[1].split('+ (void)showCameraInScene:', 1)[0]
assert 'if (image) [weakSelf acceptImage:image]' in camera_action and camera_action.index('acceptImage:image') < camera_action.index('focusInput')
assert 'completion(nil)' in camera
