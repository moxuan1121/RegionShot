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
print('Verified original preference keys/defaults/ranges and root settings destinations')
