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
hooks = read("Selection/RSFreezeSystemHooks.xm")
assert "acquireSystemGestureDisableAssertion" not in read("Selection/RSSelectionWindow.m")
assert "lockUIFromSource:" in hooks and "cancelCapture]; %orig;" in hooks
assert "gestureRecognizerShouldBegin:" in hooks and "canBePresented" in hooks
camera = read("Camera/RSInlineCamera.m")
chat = read("AI/RSChatController.m")
assert "regionshot-camera://capture" in chat and "cameraRequest" in chat
assert "AVCapturePhotoOutput" in camera and "capturePhotoWithSettings:" in camera
assert "notify_register_dispatch(RS_CAMERA_FINISHED" in chat and "[self acceptImage:image]" in chat
assert "[session stopRunning]" in camera
assert "chat.host.isKeyWindow" in chat and "!chat.cameraRequest" in chat
for folder, prefix in [("Input", "RSInput"), ("KeyboardAI", "RSKA")]:
    assert "RSPopupContentHeight(" in read(f"{folder}/{prefix}Interface.m")
    assert "safeAreaInsets.top -" not in read(f"{folder}/{prefix}Interface.m")

assert "CGFloat chrome = 22" in read("Geometry/RSPopupLayout.h")
assert "point.y <= 32" in read("Geometry/RSPanelController.h")
assert "height - 28" in read("Geometry/RSPanelController.h")

assert "AVCaptureSessionErrorKey" in camera and "AVCaptureSessionInterruptionReasonKey" in camera
assert "usesApplicationAudioSession = NO" in camera
assert "UIApplicationDidBecomeActiveNotification" in camera and "[self startSession]" in camera
camera_host = read("Camera/main.m")
assert "notify_post(RS_CAMERA_FINISHED)" in camera_host and 'NSSelectorFromString(@"suspend")' in camera_host
assert "chmod(RSCameraImagePath().fileSystemRepresentation, 0644)" in camera_host
for token_view in ("Input/RSInputTokenView.m", "KeyboardAI/RSKATokenView.m"):
    assert "- (void)clearSelection" in read(token_view)
for panel in ("Input/RSInputInterface.m", "KeyboardAI/RSKAInterface.m"):
    assert "@selector(clearTokenSelection:)" in read(panel)
