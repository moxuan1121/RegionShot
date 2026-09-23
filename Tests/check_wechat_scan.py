from pathlib import Path

root = Path(__file__).parents[1]
menu = (root / "Selection/RSMenuSettings.m").read_text(encoding="utf-8")
window = (root / "Selection/RSSelectionWindow.m").read_text(encoding="utf-8")
receiver = (root / "Input/Tweak.xm").read_text(encoding="utf-8")

assert '@"微信扫码"' in menu and '@"weixin://scanqrcode"' in window
assert "if (!RSStageWeChatScanImage(image)) return;" in window
assert 'NSUUID.UUID.UUIDString' in window and '@".request"' in window
handler = window.split("_toolbar.wechatScanHandler = ^{", 1)[1].split("};", 1)[0]
assert "saveImage:" not in handler
assert "RSConsumeWeChatScanImage()" in receiver
assert "scanPickedImage:image" in receiver
consume = receiver.split("static UIImage *RSConsumeWeChatScanImage", 1)[1].split("%group RSWeChatScanner", 1)[0]
assert "[files moveItemAtPath" not in consume and "dataWithContentsOfFile:path" in consume
assert consume.index("dataWithContentsOfFile:path") < consume.index("removeItemAtPath:path")
assert "lastWechatScanRequest" in consume
assert consume.index("setObject:request") < consume.index("removeItemAtPath:path")
scan_hook = receiver.split("%group RSWeChatScanner", 1)[1].split("%end\n%end", 1)[0]
injected_scan = scan_hook.split("@try", 1)[1]
assert injected_scan.index("setIsPickingImageFromAlbum:YES") < injected_scan.index("scanPickedImage:image") < injected_scan.index("setIsPickingImageFromAlbum:NO")
assert "@finally" in scan_hook
assert scan_hook.index("setIsPickingImageFromAlbum:NO") < scan_hook.index("%orig;")
assert 'isEqual:@"com.tencent.xin"' in receiver
print("wechat scan integration: ok")
