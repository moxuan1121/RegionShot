"""Keep configuration reads and view-tree searches off Sileo's touch path."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / 'Input/RSSileo.xm').read_text(encoding='utf-8')
touch = source.split('shouldReceiveTouch:', 1)[1].split('shouldRecognizeSimultaneously', 1)[0]
press = source.split('- (void)pressed:', 1)[1]
assert 'RSInputConfig()' not in touch and 'RSTextAtPoint' not in touch
assert 'RSInputIsPanelVisible()' in touch and 'self.enabled' in touch
assert 'UIApplicationDidBecomeActiveNotification' in source
assert 'RSTextAtPoint(gesture.view, point, 0)' in press and 'RSIsDepiction(hit)' in press
print('Sileo touch path avoids configuration I/O and view-tree search')
