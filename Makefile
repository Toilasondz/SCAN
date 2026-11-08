TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := HSONScanner
HSONScanner_FILES := HSONScanner.m
HSONScanner_FRAMEWORKS := Foundation UIKit
HSONScanner_CFLAGS := -fobjc-arc -Wall -Wextra
HSONScanner_LDFLAGS := -Wl,-dead_strip

include $(THEOS_MAKE_PATH)/tweak.mk
