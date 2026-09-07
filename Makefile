APP_NAME := Typless
BUNDLE_ID := com.typless.Typless
CONFIGURATION ?= debug
APP_BUNDLE := $(CURDIR)/.build/app/$(APP_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_EXECUTABLE := $(APP_CONTENTS)/MacOS/$(APP_NAME)
USER_APPLICATIONS_DIR ?= $(shell dscl . -read "/Users/$$(id -un)" NFSHomeDirectory | awk '{print $$2}')/Applications
INSTALLED_APP := $(USER_APPLICATIONS_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
SIGNING_IDENTITY := $(if $(strip $(CODESIGN_IDENTITY)),$(CODESIGN_IDENTITY),-)
APP_ICON := Resources/AppIcon.icns
ENTITLEMENTS := Resources/Typless.entitlements

.PHONY: build run install clean permissions reset-permissions test

build: $(APP_ICON)
	swift build -c $(CONFIGURATION)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_CONTENTS)/MacOS" "$(APP_CONTENTS)/Resources"
	cp "$$(swift build -c $(CONFIGURATION) --show-bin-path)/$(APP_NAME)" "$(APP_EXECUTABLE)"
	cp Resources/Info.plist "$(APP_CONTENTS)/Info.plist"
	ditto Resources/en.lproj "$(APP_CONTENTS)/Resources/en.lproj"
	ditto Resources/zh-Hans.lproj "$(APP_CONTENTS)/Resources/zh-Hans.lproj"
	cp "$(APP_ICON)" "$(APP_CONTENTS)/Resources/AppIcon.icns"
	cp THIRD_PARTY_NOTICES.txt "$(APP_CONTENTS)/Resources/"
	chmod 755 "$(APP_EXECUTABLE)"
	codesign --force --deep --options runtime --entitlements "$(ENTITLEMENTS)" --sign "$(SIGNING_IDENTITY)" --identifier "$(BUNDLE_ID)" "$(APP_BUNDLE)"
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"
	@echo "Signed with: $(SIGNING_IDENTITY)"

$(APP_ICON): Tools/generate_app_icon.swift
	mkdir -p "$(CURDIR)/.build"
	swift Tools/generate_app_icon.swift "$(CURDIR)/.build/Typless.iconset"
	iconutil -c icns "$(CURDIR)/.build/Typless.iconset" -o "$(APP_ICON)"

run: build
	-pkill -x "$(APP_NAME)"
	open "$(APP_BUNDLE)"

install: build
	mkdir -p "$(USER_APPLICATIONS_DIR)"
	rm -rf "$(INSTALLED_APP)"
	ditto "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP)"

test:
	swift test

permissions:
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

reset-permissions:
	tccutil reset Accessibility "$(BUNDLE_ID)"
	tccutil reset Microphone "$(BUNDLE_ID)"

clean:
	swift package clean
	rm -rf "$(CURDIR)/.build/app"
