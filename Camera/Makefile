TARGET := iphone:clang:latest:15.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = RegionShotCamera
RegionShotCamera_FILES = main.m
RegionShotCamera_FRAMEWORKS = UIKit AVFoundation
RegionShotCamera_LIBRARIES = roothide
RegionShotCamera_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
RegionShotCamera_CODESIGN_FLAGS = -SEntitlements.plist
include $(THEOS_MAKE_PATH)/application.mk
