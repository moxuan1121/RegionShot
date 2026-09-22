from pathlib import Path

root = Path(__file__).parents[1]
menu = (root / "Selection/RSMenuSettings.m").read_text(encoding="utf-8")
window = (root / "Selection/RSSelectionWindow.m").read_text(encoding="utf-8")
receiver = (root / "Input/Tweak.xm").read_text(encoding="utf-8")

assert '@"微信扫码"' in menu and '@"weixin://scanqrcode"' in window
assert "RSStageWeChatScanImage(image)" in window
handler = window.split("_toolbar.wechatScanHandler = ^{", 1)[1].split("};", 1)[0]
assert "saveImage:" not in handler
assert "RSConsumeWeChatScanImage()" in receiver
assert "scanPickedImage:image" in receiver
consume = receiver.split("static UIImage *RSConsumeWeChatScanImage", 1)[1].split("%group RSWeChatScanner", 1)[0]
assert consume.index("moveItemAtPath:path toPath:consuming") < consume.index("dataWithContentsOfFile:consuming")
assert "dataWithContentsOfFile:path" not in consume
scan_hook = receiver.split("%group RSWeChatScanner", 1)[1].split("%end\n%end", 1)[0]
assert scan_hook.index("setIsPickingImageFromAlbum:YES") < scan_hook.index("scanPickedImage:image") < scan_hook.index("setIsPickingImageFromAlbum:NO")
assert "@finally" in scan_hook
assert 'isEqual:@"com.tencent.xin"' in receiver
print("wechat scan integration: ok")
