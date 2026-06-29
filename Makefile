APP_NAME := NoSlouch
BUNDLE := $(APP_NAME).app
EXECUTABLE := .build/debug/$(APP_NAME)
SIGN_IDENTITY ?= -

.PHONY: build test bundle run clean

build:
	swift build --disable-sandbox

test:
	swift test --disable-sandbox

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(EXECUTABLE) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns; fi
	if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		codesign --force --sign - $(BUNDLE); \
	else \
		codesign --force --sign "$(SIGN_IDENTITY)" --entitlements NoSlouch.entitlements $(BUNDLE); \
	fi

run: bundle
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)
