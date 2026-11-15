TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = FreeFire

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FFESPMenu

FFESPMenu_FILES = FFESPMenu.mm
FFESPMenu_CFLAGS = -fobjc-arc -std=c++20 -O2 -Wall -Wextra
FFESPMenu_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
