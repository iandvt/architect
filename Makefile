APP_DIR ?= .tmp/current-apps
STABLE_APP := $(APP_DIR)/Architect (Stable).app
SCRATCH_APP := $(APP_DIR)/Architect (Scratch).app
APPLICATIONS_DIR ?= /Applications
INSTALLED_STABLE_APP := $(APPLICATIONS_DIR)/Architect (Stable).app
INSTALLED_SCRATCH_APP := $(APPLICATIONS_DIR)/Architect (Scratch).app
ARCHITECT_BIN ?= zig-out/bin/architect
BUNDLE_SCRIPT ?= ./scripts/bundle-macos.sh
CONFIG_ROOT ?= $(HOME)/.config/architect
INSTANCES_DIR ?= $(CONFIG_ROOT)/instances
LSREGISTER ?= /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
OPEN ?= open
SESSION ?=
ZIG ?= zig
CURRENT_BRANCH := $(shell git branch --show-current 2>/dev/null)
ifeq ($(CURRENT_BRANCH),main)
CURRENT_CHANNEL := Stable
CURRENT_APP := $(STABLE_APP)
CURRENT_INSTALLED_APP := $(INSTALLED_STABLE_APP)
else
ifeq ($(CURRENT_BRANCH),scratch)
CURRENT_CHANNEL := Scratch
CURRENT_APP := $(SCRATCH_APP)
CURRENT_INSTALLED_APP := $(INSTALLED_SCRATCH_APP)
else
CURRENT_CHANNEL :=
CURRENT_APP :=
CURRENT_INSTALLED_APP :=
endif
endif

.DEFAULT_GOAL := help

.PHONY: help apps current-app publish-apps publish-current-app dock-icons stable scratch stable-new scratch-new stable-restore scratch-restore sessions check-installed-stable-app check-installed-scratch-app check-installed-apps require-channel-branch require-session

help:
	@printf '%s\n' \
		'Architect app launcher targets:' \
		'  make apps                              Rebuild local app bundle for this branch' \
		'  make publish-apps                      Rebuild/install this branch app and refresh Dock icons' \
		'                                         main -> Stable, scratch -> Scratch' \
		'  make stable                            Launch installed Stable app' \
		'  make stable SESSION=HappyOtter         Restore installed Stable app session' \
		'  make scratch                           Launch installed Scratch app' \
		'  make scratch SESSION=BoldBadger        Restore installed Scratch app session' \
		'  make stable-new                        Launch installed Stable app' \
		'  make stable-restore SESSION=HappyOtter Restore installed Stable app session' \
		'  make scratch-new                       Launch installed Scratch app' \
		'  make scratch-restore SESSION=BoldBadger Restore installed Scratch app session' \
		'  make sessions                          List saved named sessions'

apps: current-app

current-app: require-channel-branch
	. ./scripts/setup-macos-sdk-workaround.sh >/tmp/architect-sdk-workaround.log && $(ZIG) build -Doptimize=ReleaseFast
	$(BUNDLE_SCRIPT) "$(ARCHITECT_BIN)" "$(APP_DIR)" --app-name "Architect ($(CURRENT_CHANNEL))"

publish-apps: publish-current-app dock-icons

publish-current-app: current-app
	@printf 'Publishing %s app bundle from branch %s to %s\n' "$(CURRENT_CHANNEL)" "$(CURRENT_BRANCH)" "$(APPLICATIONS_DIR)"
	rm -rf "$(CURRENT_INSTALLED_APP)"
	cp -R "$(CURRENT_APP)" "$(APPLICATIONS_DIR)/"
	xattr -dr com.apple.quarantine "$(CURRENT_INSTALLED_APP)" 2>/dev/null || true
	@if [ -x "$(LSREGISTER)" ]; then \
		"$(LSREGISTER)" -f "$(CURRENT_INSTALLED_APP)"; \
	fi

dock-icons:
	@plist="$$HOME/Library/Preferences/com.apple.dock.plist"; \
	if [ "$$(uname -s)" != "Darwin" ]; then \
		printf 'Dock refresh is only supported on macOS\n'; \
		exit 0; \
	fi; \
	if [ ! -d "$(INSTALLED_STABLE_APP)" ] && [ ! -d "$(INSTALLED_SCRATCH_APP)" ]; then \
		printf 'No installed Architect app bundles found under %s\n' "$(APPLICATIONS_DIR)" >&2; \
		printf 'Install Stable from main or Scratch from scratch with: make publish-apps\n' >&2; \
		exit 1; \
	fi; \
	if [ ! -f "$$plist" ]; then \
		defaults write com.apple.dock persistent-apps -array; \
	fi; \
	i=0; \
	while /usr/libexec/PlistBuddy -c "Print :persistent-apps:$$i" "$$plist" >/dev/null 2>&1; do \
		bundle=$$(/usr/libexec/PlistBuddy -c "Print :persistent-apps:$$i:tile-data:bundle-identifier" "$$plist" 2>/dev/null || true); \
		label=$$(/usr/libexec/PlistBuddy -c "Print :persistent-apps:$$i:tile-data:file-label" "$$plist" 2>/dev/null || true); \
		url=$$(/usr/libexec/PlistBuddy -c "Print :persistent-apps:$$i:tile-data:file-data:_CFURLString" "$$plist" 2>/dev/null || true); \
		if [ "$$bundle" = "com.forketyfork.architect.stable" ] || \
		   [ "$$bundle" = "com.forketyfork.architect.scratch" ] || \
		   [ "$$label" = "Architect (Stable)" ] || \
		   [ "$$label" = "Architect (Scratch)" ] || \
		   [ "$$url" = "file:///Applications/Architect%20(Stable).app/" ] || \
		   [ "$$url" = "file:///Applications/Architect%20(Scratch).app/" ]; then \
			/usr/libexec/PlistBuddy -c "Delete :persistent-apps:$$i" "$$plist" >/dev/null; \
			continue; \
		fi; \
		i=$$((i + 1)); \
	done
	if [ -d "$(INSTALLED_STABLE_APP)" ]; then \
		defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file:///Applications/Architect%20(Stable).app/</string><key>_CFURLStringType</key><integer>15</integer></dict><key>file-label</key><string>Architect (Stable)</string><key>file-type</key><integer>41</integer></dict><key>tile-type</key><string>file-tile</string></dict>'; \
	fi; \
	if [ -d "$(INSTALLED_SCRATCH_APP)" ]; then \
		defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file:///Applications/Architect%20(Scratch).app/</string><key>_CFURLStringType</key><integer>15</integer></dict><key>file-label</key><string>Architect (Scratch)</string><key>file-type</key><integer>41</integer></dict><key>tile-type</key><string>file-tile</string></dict>'; \
	fi; \
	killall Dock >/dev/null 2>&1 || true

stable: check-installed-stable-app
	@if [ -n "$(SESSION)" ]; then \
		printf 'Restoring Stable session: %s\n' "$(SESSION)"; \
		$(OPEN) -n "$(INSTALLED_STABLE_APP)" --args --session "$(SESSION)"; \
	else \
		printf 'Launching new Stable session\n'; \
		$(OPEN) -n "$(INSTALLED_STABLE_APP)"; \
	fi

scratch: check-installed-scratch-app
	@if [ -n "$(SESSION)" ]; then \
		printf 'Restoring Scratch session: %s\n' "$(SESSION)"; \
		$(OPEN) -n "$(INSTALLED_SCRATCH_APP)" --args --session "$(SESSION)"; \
	else \
		printf 'Launching new Scratch session\n'; \
		$(OPEN) -n "$(INSTALLED_SCRATCH_APP)"; \
	fi

stable-new: check-installed-stable-app
	$(OPEN) -n "$(INSTALLED_STABLE_APP)"

scratch-new: check-installed-scratch-app
	$(OPEN) -n "$(INSTALLED_SCRATCH_APP)"

stable-restore: require-session check-installed-stable-app
	$(OPEN) -n "$(INSTALLED_STABLE_APP)" --args --session "$(SESSION)"

scratch-restore: require-session check-installed-scratch-app
	$(OPEN) -n "$(INSTALLED_SCRATCH_APP)" --args --session "$(SESSION)"

sessions:
	@root="$(INSTANCES_DIR)"; \
	if [ ! -d "$$root" ]; then \
		printf 'No Architect sessions found at %s\n' "$$root"; \
		exit 0; \
	fi; \
	find "$$root" -mindepth 2 -maxdepth 2 -type d | sort | while IFS= read -r session_dir; do \
		channel=$$(basename "$$(dirname "$$session_dir")"); \
		session=$$(basename "$$session_dir"); \
		display=$$(sed -n 's/^display_name = "\(.*\)"$$/\1/p' "$$session_dir/instance.toml" 2>/dev/null | head -1); \
		emoji=$$(sed -n 's/^emoji = "\(.*\)"$$/\1/p' "$$session_dir/instance.toml" 2>/dev/null | head -1); \
		if [ -n "$$display" ] || [ -n "$$emoji" ]; then \
			printf '%s/%s  %s %s\n' "$$channel" "$$session" "$$emoji" "$$display"; \
		else \
			printf '%s/%s\n' "$$channel" "$$session"; \
		fi; \
	done

require-channel-branch:
	@if [ -z "$(CURRENT_CHANNEL)" ]; then \
		printf 'Current branch "%s" does not map to an app channel. Use main for Stable or scratch for Scratch.\n' "$(CURRENT_BRANCH)" >&2; \
		exit 1; \
	fi

require-session:
	@if [ -z "$(SESSION)" ]; then \
		printf 'SESSION is required. Example: make stable-restore SESSION=HappyOtter\n' >&2; \
		exit 1; \
	fi

check-installed-stable-app:
	@if [ ! -d "$(INSTALLED_STABLE_APP)" ]; then \
		printf 'Missing installed Stable app bundle: %s\n' "$(INSTALLED_STABLE_APP)" >&2; \
		printf 'Install Stable from main with: make publish-apps\n' >&2; \
		exit 1; \
	fi

check-installed-scratch-app:
	@if [ ! -d "$(INSTALLED_SCRATCH_APP)" ]; then \
		printf 'Missing installed Scratch app bundle: %s\n' "$(INSTALLED_SCRATCH_APP)" >&2; \
		printf 'Install Scratch from scratch with: make publish-apps\n' >&2; \
		exit 1; \
	fi

check-installed-apps:
	@if [ ! -d "$(INSTALLED_STABLE_APP)" ] || [ ! -d "$(INSTALLED_SCRATCH_APP)" ]; then \
		printf 'Missing installed app bundles under %s\n' "$(APPLICATIONS_DIR)" >&2; \
		printf 'Install Stable from main and Scratch from scratch with: make publish-apps\n' >&2; \
		exit 1; \
	fi
