APP_NAME := NoSlouch
BUNDLE ?= $(APP_NAME).app
CONFIGURATION ?= debug
BUILD_DIR ?= .build
EXECUTABLE = $(BUILD_DIR)/$(CONFIGURATION)/$(APP_NAME)
SIGN_IDENTITY ?= -
DMG := $(APP_NAME).dmg
NOTARY_PROFILE ?= noslouch-notary
LINT_PATHS := Package.swift Sources Tests

.PHONY: build test lint format bundle release-bundle verify-bundle run dmg notarize clean

build:
	swift build --disable-sandbox --configuration $(CONFIGURATION) --scratch-path $(BUILD_DIR)

test:
	swift test --disable-sandbox

lint:
	swift format lint --recursive --strict $(LINT_PATHS)

format:
	swift format format --recursive --in-place $(LINT_PATHS)

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(EXECUTABLE) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns; fi
	if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		codesign --force --options runtime --sign - $(BUNDLE); \
	else \
		codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" --entitlements NoSlouch.entitlements $(BUNDLE); \
	fi

release-bundle:
	$(MAKE) bundle CONFIGURATION=release BUILD_DIR=/tmp/noslouch-release-build
	$(MAKE) verify-bundle

verify-bundle:
	codesign --verify --deep --strict --verbose=2 $(BUNDLE)
	codesign --display --verbose=4 $(BUNDLE) 2>&1 | grep -q 'flags=.*runtime'
	plutil -lint $(BUNDLE)/Contents/Info.plist

run: bundle
	open $(BUNDLE)

# Disk image for distribution (F4). Works with ad-hoc signing for local
# testing; a real release needs SIGN_IDENTITY set to a Developer ID
# Application certificate and physical-device verification.
dmg: release-bundle
	rm -rf dist $(DMG)
	mkdir -p dist/$(APP_NAME)
	cp -R $(BUNDLE) dist/$(APP_NAME)/
	ln -s /Applications dist/$(APP_NAME)/Applications
	hdiutil create -volname $(APP_NAME) -srcfolder dist/$(APP_NAME) -ov -format UDZO $(DMG)
	rm -rf dist

# Requires: SIGN_IDENTITY='Developer ID Application: …' and a notarytool
# keychain profile (xcrun notarytool store-credentials $(NOTARY_PROFILE)).
# See docs/dev/RELEASE.md for the full runbook.
notarize:
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		echo "error: notarize needs a Developer ID. Run:"; \
		echo "  make notarize SIGN_IDENTITY='Developer ID Application: <name> (<team>)'"; \
		exit 1; \
	fi
	$(MAKE) dmg SIGN_IDENTITY="$(SIGN_IDENTITY)"
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)
	xcrun stapler validate $(DMG)
	spctl --assess --type execute --verbose=2 $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE) $(DMG) dist
