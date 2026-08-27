TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYPluginMgr

DYPluginMgr_FILES = Tweak.x DYPluginModel.m DYPluginsMgr.m DYPluginsViewController.m
DYPluginMgr_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DYPluginMgr_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

