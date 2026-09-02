TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYStorage

DYStorage_FILES = Tweak.xm DYStorageManager.m
DYStorage_CFLAGS = -fobjc-arc -fobjc-arc-exceptions -Wno-deprecated-declarations -Wno-unguarded-availability
DYStorage_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
