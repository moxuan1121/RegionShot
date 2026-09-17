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
assert "UIScrollViewDelegate" in editor
assert "self.zoomView.maximumZoomScale = 6.0" in editor
assert "self.zoomView.panGestureRecognizer.minimumNumberOfTouches = 2" in editor
assert "return self.zoomContentView" in editor
assert "[self.canvas cancelCurrentStroke]" in editor
assert "- (void)cancelCurrentStroke" in canvas
assert "self.multipleTouchEnabled = YES" in canvas
assert canvas.count("event.allTouches.count > 1") == 2
assert "UITapGestureRecognizer *textTap" in editor
assert "[self.canvas addGestureRecognizer:self.textTap]" in editor
assert "RSMarkupAnnotationItem *item = [self.canvas textItemAtPoint:point]" in editor
assert "item.textAnnotation = a" in editor
assert "isAddingText" not in editor
assert "[self presentViewController:vc animated:YES completion:nil]" in editor
assert "UILongPressGestureRecognizer" in canvas
assert "textItemAtPoint:" in canvas
assert "self.movingTextItem.textAnnotation.center =" in canvas
assert "self.items.reverseObjectEnumerator" in canvas
assert "UIImpactFeedbackGenerator" in canvas.split("- (void)moveText:", 1)[1].split("#pragma mark - Drawing", 1)[0]
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

selection_window = read("Selection/RSSelectionWindow.m")
edit_selection = selection_window.split("- (void)editSelection", 1)[1].split("- (void)show", 1)[0]
assert "UIModalPresentationFullScreen" in edit_selection
assert "presentViewController:navigation" in edit_selection
assert "addChildViewController:navigation" not in edit_selection
toolbar = read("Selection/RSSelectionToolbar.m")
assert "RSMenuImpact();" in toolbar
assert '@"presentation"] isEqual:@"keyboardai"' in toolbar
hooks = read("Selection/RSFreezeSystemHooks.xm")
assert "acquireSystemGestureDisableAssertion" not in read("Selection/RSSelectionWindow.m")
assert "lockUIFromSource:" in hooks and "cancelCapture]; %orig;" in hooks
assert "gestureRecognizerShouldBegin:" in hooks and "canBePresented" in hooks
chat = read("AI/RSChatController.m")
for folder, prefix in [("Input", "RSInput"), ("KeyboardAI", "RSKA")]:
    assert "RSPopupContentHeight(" in read(f"{folder}/{prefix}Interface.m")
    assert "safeAreaInsets.top -" not in read(f"{folder}/{prefix}Interface.m")

assert "CGFloat chrome = 22" in read("Geometry/RSPopupLayout.h")
assert "contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever" in read("Geometry/RSPopupLayout.h")
assert "point.y <= 32" in read("Geometry/RSPanelController.h")
assert "height - 28" in read("Geometry/RSPanelController.h")

for token_view in ("Input/RSInputTokenView.m", "KeyboardAI/RSKATokenView.m"):
    source = read(token_view)
    assert "- (void)clearSelection" in source
    assert "selectionOrder" in source
    assert "for (NSNumber *value in self.selectionOrder)" in source
for panel in ("Input/RSInputInterface.m", "KeyboardAI/RSKAInterface.m"):
    assert "@selector(clearTokenSelection:)" in read(panel)
assert "chat.host.isKeyWindow" in chat
assert "UTTypeItem" in chat
assert '@"file_data"' in read("AI/RSChatAttachments.h") and '@"filename"' in read("AI/RSChatAttachments.h")
