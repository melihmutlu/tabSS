APP_NAME   := tabSS
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_TO := $(HOME)/Applications/$(APP_NAME).app
CERT_NAME  := tabSS Local Signing
CODESIGN   := /usr/bin/codesign
SECURITY   := /usr/bin/security
KEYCHAIN   := $(HOME)/Library/Keychains/login.keychain-db

# Sign by certificate hash from the login keychain, so a look-alike name elsewhere can't be picked.
ifeq ($(origin SIGN_ID),undefined)
SIGN_ID := $(shell $(SECURITY) find-identity -p codesigning "$(KEYCHAIN)" | awk -F'"' '$$2 == "$(CERT_NAME)" { split($$1, f, " "); print f[2]; exit }')
ifeq ($(SIGN_ID),)
SIGN_ID := -
SIGN_WARNING := warning: '$(CERT_NAME)' not found, signing ad-hoc; run 'make cert' so privacy grants survive rebuilds
endif
endif

.PHONY: all build app sign install uninstall test smoke cert clean stop

all: sign

# SwiftPM stamps the deployment target as the SDK version; AppKit keys current system visuals off the real SDK.
MIN_MACOS   := 14.0
SDK_VERSION := $(shell xcrun --sdk macosx --show-sdk-version)
SWIFT_BUILD := swift build -c release -Xlinker -platform_version -Xlinker macos -Xlinker $(MIN_MACOS) -Xlinker $(SDK_VERSION)

build:
	$(SWIFT_BUILD)

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$($(SWIFT_BUILD) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"

sign: app
	$(if $(SIGN_WARNING),@echo "$(SIGN_WARNING)")
	$(CODESIGN) --force --options runtime --timestamp=none --sign "$(SIGN_ID)" "$(APP)"
	$(CODESIGN) --verify --strict "$(APP)"

stop:
	@pkill -x "$(APP_NAME)" || true
	@for _ in $$(seq 50); do pgrep -x "$(APP_NAME)" >/dev/null || exit 0; sleep 0.1; done; pkill -9 -x "$(APP_NAME)" || true

install: sign stop
	rm -rf "$(INSTALL_TO)"
	cp -R "$(APP)" "$(INSTALL_TO)"
	open "$(INSTALL_TO)"

uninstall: stop
	rm -rf "$(INSTALL_TO)"

test:
	swift test

smoke:
	Scripts/smoke.sh "$(INSTALL_TO)"

cert:
	Scripts/create-signing-cert.sh "$(CERT_NAME)"

clean:
	rm -rf .build "$(BUILD_DIR)"
