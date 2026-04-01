APP_NAME := cobrain
SCHEME := $(APP_NAME)
ARCHIVE_PATH := build/$(APP_NAME).xcarchive
EXPORT_DIR := build/export
APP_PATH := $(EXPORT_DIR)/$(APP_NAME).app
DMG_PATH := build/$(APP_NAME).dmg
APPCAST_DIR := docs

VERSION := $(shell grep 'CFBundleShortVersionString' Project.swift | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')

NOTARY_PROFILE ?= cobrain-notary

.PHONY: all generate archive export dmg notarize appcast upload release clean bump cask-install

all: release

## generate: Install dependencies and generate the Xcode project
generate:
	mise exec -- tuist install
	mise exec -- tuist generate

## archive: Build an xcarchive with Developer ID signing
archive:
	xcodebuild archive \
		-workspace $(APP_NAME).xcworkspace \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath $(ARCHIVE_PATH) \
		CODE_SIGN_IDENTITY="Developer ID Application" \
		DEVELOPMENT_TEAM=6JS29H9GMN \
		CODE_SIGN_STYLE=Manual \
		ENABLE_HARDENED_RUNTIME=YES \
		-skipPackagePluginValidation

## export: Export the .app from the archive
export:
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportOptionsPlist ExportOptions.plist \
		-exportPath $(EXPORT_DIR)

## dmg: Create a DMG with drag-to-Applications layout
dmg:
	rm -f $(DMG_PATH)
	mkdir -p build/dmg
	cp -R $(APP_PATH) build/dmg/
	ln -sf /Applications build/dmg/Applications
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder build/dmg \
		-ov -format UDZO \
		$(DMG_PATH)
	rm -rf build/dmg

## notarize: Submit to Apple notarization, staple, and re-create DMG
notarize:
	xcrun notarytool submit $(DMG_PATH) \
		--keychain-profile $(NOTARY_PROFILE) \
		--wait
	xcrun stapler staple $(DMG_PATH)

## appcast: Generate appcast.xml into docs/ for GitHub Pages
appcast:
	$(eval SPARKLE_BIN := $(shell \
		find Tuist/.build -path '*/Sparkle/bin/generate_appcast' -type f 2>/dev/null | head -1 || true; \
	))
	$(eval SPARKLE_BIN := $(if $(SPARKLE_BIN),$(SPARKLE_BIN),$(shell \
		find ~/Library/Developer/Xcode/DerivedData -path '*/Sparkle/generate_appcast' -type f 2>/dev/null | head -1 || true; \
	)))
	@if [ -z "$(SPARKLE_BIN)" ]; then \
		echo "Error: generate_appcast not found. Run 'tuist install' or build the project first."; \
		exit 1; \
	fi
	mkdir -p $(APPCAST_DIR)
	cp $(DMG_PATH) $(APPCAST_DIR)/
	$(SPARKLE_BIN) \
		--download-url-prefix "https://github.com/FuntasticOutliers/cobrain/releases/download/v$(VERSION)/" \
		$(APPCAST_DIR)

## bump: Increment patch version in Project.swift
bump:
	@CURRENT=$(VERSION); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT | cut -d. -f2); \
	PATCH=$$(echo $$CURRENT | cut -d. -f3); \
	NEW="$$MAJOR.$$MINOR.$$((PATCH + 1))"; \
	sed -i '' "s/\"CFBundleShortVersionString\": \"$$CURRENT\"/\"CFBundleShortVersionString\": \"$$NEW\"/" Project.swift; \
	echo "Bumped version: $$CURRENT -> $$NEW"

## upload: Create a GitHub release, upload the DMG, and push appcast to GitHub Pages
upload:
	$(eval VERSION := $(shell grep 'CFBundleShortVersionString' Project.swift | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/'))
	gh release create v$(VERSION) $(DMG_PATH) \
		--title "v$(VERSION)" \
		--generate-notes
	git add $(APPCAST_DIR)/appcast.xml
	git commit -m "Update appcast for v$(VERSION)"
	git push

## release: Full release pipeline
release: bump generate archive export dmg notarize appcast upload
	@echo ""
	@echo "Release v$(VERSION) complete!"

## cask-install: Install via Homebrew cask from local definition
cask-install:
	brew install --cask Casks/cobrain.rb

## clean: Remove build artifacts
clean:
	rm -rf build/
