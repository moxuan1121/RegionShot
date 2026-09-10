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
assert 'isEqual:@"com.tencent.xin"' in receiver
print("wechat scan integration: ok")
