# Local overrides such as THEOS or SDK paths can live in Makefile.local.
-include Makefile.local

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

# Match DYYY's package interface: rootless by default, with explicit schemes
# available through SCHEME=rootful/rootless/roothide.
SCHEME ?= rootless
ifeq ($(SCHEME),roothide)
    export THEOS_PACKAGE_SCHEME = roothide
    export FINALPACKAGE = 1
else ifeq ($(SCHEME),rootful)
    unexport THEOS_PACKAGE_SCHEME
else ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
    export FINALPACKAGE = 1
else
    $(error Unknown SCHEME=$(SCHEME); use rootless, rootful, or roothide)
endif

ifeq ($(GITHUB_ACTIONS),true)
    export INSTALL = 0
    export FINALPACKAGE = 1
endif

export DEBUG = 0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYStorage

DYStorage_FILES = Tweak.xm DYStorageManager.m DYStorageDeveloperScanner.m
DYStorage_CFLAGS = -fobjc-arc -fobjc-arc-exceptions -Wno-deprecated-declarations -Wno-unguarded-availability
DYStorage_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	@rm -rf .theos packages

after-package::
	@echo "Packaging complete."
