TARGET := iphone:clang:latest:15.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RegionShot RegionShotInput RegionShotURLs
RegionShot_FILES = Trigger.xm \
	Preferences/RSOptions.m \
	Preferences/RSBehaviorSettings.m \
	History/RSHistoryStore.m \
	History/RSHistoryController.m \
	Manager/RSRegionShotManager.m \
	Capture/RSScreenCapture.m \
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
	AI/RSSSEDecoder.m \
	KeyboardAI/RSKAInterface.m \
	KeyboardAI/RSKATokenView.m \
	KeyboardAI/RSKAAnchoredMenuView.m
RegionShot_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
RegionShot_FRAMEWORKS = Foundation UIKit Photos QuartzCore Security PhotosUI UniformTypeIdentifiers Vision CoreImage PencilKit

RegionShotURLs_FILES = Preferences/RSURLHooks.xm
RegionShotURLs_CFLAGS = -fobjc-arc -Wall -Wextra
RegionShotURLs_FRAMEWORKS = UIKit Foundation
RegionShotInput_FILES = Input/Tweak.xm Input/RSSileo.xm Input/RSInputInterface.m Input/RSInputStream.m Input/RSInputStore.m Input/RSInputTokenView.m Input/RSInputClipboard.m Input/RSInputAnchoredMenuView.m
RegionShotInput_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
RegionShotInput_FRAMEWORKS = UIKit Foundation WebKit
RegionShotInput_LIBRARIES = roothide
RegionShot_LIBRARIES = roothide
RegionShot_FILES += Input/RSInputStore.m Input/RSInputOptionsController.m
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
