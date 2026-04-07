ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CustomDockPreferences

CustomDockPreferences_FILES = CustomDockPreferences.mm
CustomDockPreferences_INSTALL_PATH = /Library/PreferenceBundles
CustomDockPreferences_CFLAGS = -fobjc-arc
CustomDockPreferences_FRAMEWORKS = UIKit
CustomDockPreferences_PRIVATE_FRAMEWORKS = Preferences
CustomDockPreferences_LDFLAGS = -F$(THEOS_SDKS_PATH)/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CustomDock.plist$(ECHO_END)
