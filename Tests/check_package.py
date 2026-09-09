"""Validate the installable package, including its previously missing Settings bundle."""
import io
import plistlib
import struct
import sys
import tarfile
from pathlib import Path

raw = Path(sys.argv[1]).read_bytes()
assert raw[:8] == b'!<arch>\n'
offset, files = 8, {}
while offset < len(raw):
    header = raw[offset:offset + 60]
    assert header[58:] == b'`\n'
    length = int(header[48:58])
    name = header[:16].decode().strip().rstrip('/')
    if name.startswith(('control.tar', 'data.tar')):
        with tarfile.open(fileobj=io.BytesIO(raw[offset + 60:offset + 60 + length])) as archive:
            for member in archive.getmembers():
                if member.isfile():
                    files[member.name.removeprefix('./')] = archive.extractfile(member).read()
    offset += 60 + length + length % 2
control = dict(line.split(': ', 1) for line in files['control'].decode().splitlines() if ': ' in line)
assert 'preferenceloader' in control['Depends']
assert control['Architecture'] == 'iphoneos-arm64e'
loader = plistlib.loads(files['Library/PreferenceLoader/Preferences/RegionShot.plist'])['entry']
bundle = 'Library/PreferenceBundles/' + loader['bundle'] + '.bundle/'
info = plistlib.loads(files[bundle + 'Info.plist'])
assert loader['detail'] == info['NSPrincipalClass'] == 'RSPreferences'
assert info['CFBundleVersion'] == control['Version'].removesuffix('-roothide')
assert loader['icon'] == 'RegionShotIcon.png'
for name, size in [('RegionShotIcon.png', 29), ('RegionShotIcon@2x.png', 58), ('RegionShotIcon@3x.png', 87)]:
    png = files['Library/PreferenceLoader/Preferences/' + name]
    assert png[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack_from('>II', png, 16) == (size, size)
    assert png[25] == 6
for path in ['Library/MobileSubstrate/DynamicLibraries/' + name + '.dylib' for name in ['RegionShot', 'RegionShotInput']] + [bundle + info['CFBundleExecutable'], 'Applications/RegionShotCamera.app/RegionShotCamera']:
    binary = files[path]
    assert struct.unpack_from('<III', binary) == (0xfeedfacf, 0x100000c, 0x80000002), path
    offset, signed = 32, False
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        command, length = struct.unpack_from('<II', binary, offset)
        if command == 0x1d:
            start, size = struct.unpack_from('<II', binary, offset + 8)
            assert start + size <= len(binary) and size > 20
            assert struct.unpack_from('>I', binary, start)[0] == 0xfade0cc0
            signed = True
        offset += length
    assert signed, path
print('Verified PreferenceLoader registration, Settings controller/version, signed modern arm64e binaries')

assert sum(p.startswith("Library/PreferenceLoader/Preferences/") and p.endswith('.plist') for p in files) == 1
assert not any("RegionShotScroll" in p or "RSLongCapture" in p for p in files)
assert not any(p.startswith('usr/share/doc/com.moxuan.regionshot/') for p in files)

camera_info = plistlib.loads(files['Applications/RegionShotCamera.app/Info.plist'])
assert camera_info['NSCameraUsageDescription']
assert 'regionshot-camera' in camera_info['CFBundleURLTypes'][0]['CFBundleURLSchemes']

assert sorted(p.rsplit('/', 1)[-1] for p in files if p.startswith('Library/MobileSubstrate/DynamicLibraries/') and p.endswith('.dylib')) == ['RegionShot.dylib', 'RegionShotInput.dylib']
assert not any('RegionShotURLs' in p for p in files)

input_filter = plistlib.loads(files['Library/MobileSubstrate/DynamicLibraries/RegionShotInput.plist'])['Filter']['Bundles']
assert 'com.apple.Preferences' not in input_filter and 'com.apple.mobilesafari' not in input_filter
