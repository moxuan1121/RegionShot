from pathlib import Path
root = Path(__file__).resolve().parents[1]
read = lambda path: (root / path).read_text(encoding="utf-8")
canvas = read("Annotation/RSMarkupAnnotationCanvas.m")
editor = read("Annotation/RSMarkupAnnotationViewController.m")
assert "self.completion = completion" in read("Selection/RSImageEditor.m")
assert "[self drawRect:self.bounds]" in canvas.split("- (UIImage *)renderedImage")[1]
assert "case RSMarkupDrawModeText:" in canvas
assert "item.textAnnotation = a" in editor
assert "CGImageGetWidth(self.sourceImage.CGImage)" in canvas
assert "resizeDrawingToSize:disp.size" in editor
assert "[self layoutToolbarButtons];" in editor.split("- (void)viewDidLayoutSubviews")[1].split("- (CGRect)imageDisplayRect")[0]
assert "forceDestroyOnRotation" not in editor
assert "Snapper3.h" not in editor
print("Annotation entry, text/highlight export, pixel sampling and layout wiring verified")

for path in ["Input/RSInputInterface.m", "KeyboardAI/RSKAInterface.m"]:
    popup = read(path)
    assert "host.keyboardLayoutGuide.topAnchor" not in popup
    assert "insertArrangedSubview:self.tokenView atIndex:1" in popup
assert "lockcomplete" in read("Trigger.xm")
assert "if (!record) snap.center" in read("Manager/RSRegionShotManager.m")

assert "addChildViewController:navigation" in read("Selection/RSSelectionWindow.m")
assert "performSinglePressAction" in read("Trigger.xm")
assert "exceptSystemGestureTypes:" in read("Selection/RSSelectionWindow.m")
assert "[NSSet set]" in read("Selection/RSSelectionWindow.m")
for folder, prefix in [("Input", "RSInput"), ("KeyboardAI", "RSKA")]:
    assert "RSPopupContentHeight(" in read(f"{folder}/{prefix}Interface.m")
    assert "safeAreaInsets.top -" not in read(f"{folder}/{prefix}Interface.m")

assert "CGFloat chrome = 22" in read("Geometry/RSPopupLayout.h")
assert "point.y <= 32" in read("Geometry/RSPanelController.h")
assert "height - 28" in read("Geometry/RSPanelController.h")
