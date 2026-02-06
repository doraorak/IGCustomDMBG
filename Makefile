TARGET := iphone:clang:latest:15.0
GO_EASY_ON_ME = 1
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IGCustomDMBG

IGCustomDMBG_FILES = Tweak.x
IGCustomDMBG_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
