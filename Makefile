TARGET := iphone:clang:latest:15.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RegionShot
RegionShot_FILES = Tweak.xm \
	Manager/RSRegionShotManager.m \
	Capture/RSScreenCapture.m \
	Selection/RSSelectionWindow.m \
	Selection/RSSelectionView.m \
	Selection/RSSelectionToolbar.m \
	Floating/RSFloatingWindow.m \
	Floating/RSFloatingImageView.m
RegionShot_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
RegionShot_FRAMEWORKS = Foundation UIKit Photos QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
