TARGET := iphone:clang:latest:15.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RegionShot
RegionShot_FILES = Trigger.xm \
	Preferences/RSOptions.m \
	History/RSHistoryStore.m \
	History/RSHistoryController.m \
	Manager/RSRegionShotManager.m \
	Capture/RSScreenCapture.m \
	Capture/RSLongCaptureWindow.m \
	Selection/RSSelectionWindow.m \
	Selection/RSSelectionView.m \
	Selection/RSSelectionToolbar.m \
	Selection/RSMenuSettings.m \
	Selection/RSRecognitionController.m \
	Selection/RSImageEditor.m \
	Floating/RSFloatingWindow.m \
	Floating/RSFloatingImageView.m \
	AI/RSChatController.m \
	AI/RSAISettingsController.m \
	AI/RSSSEDecoder.m
RegionShot_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
RegionShot_FRAMEWORKS = Foundation UIKit Photos QuartzCore Security PhotosUI UniformTypeIdentifiers Vision CoreImage PencilKit

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
