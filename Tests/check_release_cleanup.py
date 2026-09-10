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
chat = (root / 'AI/RSChatController.m').read_text(encoding='utf-8')
assert '能否解析此文件取决于' not in chat
assert 'size.unsignedLongLongValue <= 64 * 1024 * 1024' in chat
assert 'data.length > 64 * 1024 * 1024' in chat
for name in ('Input/RSInputInterface.m', 'KeyboardAI/RSKAInterface.m'):
    panel = (root / name).read_text(encoding='utf-8')
    assert '[self observePanelEvents];' in panel
    close = panel.split('- (void)close {', 1)[1]
    assert '[NSNotificationCenter.defaultCenter removeObserver:self];' in close
print('Verified release hygiene, bounded model requests and stale callback guards')
floating = (root / 'Floating/RSFloatingWindow.m').read_text(encoding='utf-8')
assert 'centerImages' not in floating and 'view.center =' not in floating
assert 'controller.targetOrientation == orientation' in floating
for name in ('Input/RSInputInterface.m', 'KeyboardAI/RSKAInterface.m'):
    source = (root / name).read_text(encoding='utf-8').split('- (void)showSearchMenu:', 1)[1]
    assert 'RSInputVisibleActions(@"clipboardHiddenPersonas")' in source
    assert '!self.tokenView ||' not in source
