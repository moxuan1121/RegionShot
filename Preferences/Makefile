ARCHS = arm64e
TARGET = iphone:clang:15.6:15.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = RegionShotPreferences
RegionShotPreferences_FILES = RSPreferences.m RSBehaviorSettings.m RSOptions.m ../Selection/RSMenuSettings.m ../AI/RSAISettingsController.m
RegionShotPreferences_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
RegionShotPreferences_FRAMEWORKS = UIKit Foundation PhotosUI UniformTypeIdentifiers Security
RegionShotPreferences_PRIVATE_FRAMEWORKS = Preferences
RegionShotPreferences_INSTALL_PATH = /Library/PreferenceBundles
include $(THEOS_MAKE_PATH)/bundle.mk
