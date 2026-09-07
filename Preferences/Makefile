ARCHS = arm64e
TARGET = iphone:clang:15.6:15.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = RegionShotPreferences
RegionShotPreferences_FILES = RSPreferences.m ../Selection/RSMenuSettings.m
RegionShotPreferences_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
RegionShotPreferences_FRAMEWORKS = UIKit Foundation PhotosUI UniformTypeIdentifiers
RegionShotPreferences_PRIVATE_FRAMEWORKS = Preferences
RegionShotPreferences_INSTALL_PATH = /Library/PreferenceBundles
include $(THEOS_MAKE_PATH)/bundle.mk
