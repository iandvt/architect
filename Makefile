APP_DIR ?= .tmp/current-apps
STABLE_APP := $(APP_DIR)/Architect (Stable).app
SCRATCH_APP := $(APP_DIR)/Architect (Scratch).app
ARCHITECT_BIN ?= zig-out/bin/architect
BUNDLE_SCRIPT ?= ./scripts/bundle-macos.sh
CONFIG_ROOT ?= $(HOME)/.config/architect
INSTANCES_DIR ?= $(CONFIG_ROOT)/instances
OPEN ?= open
SESSION ?=
ZIG ?= zig

.DEFAULT_GOAL := help

.PHONY: help apps stable scratch stable-new scratch-new stable-restore scratch-restore sessions check-stable-app check-scratch-app require-session

help:
	@printf '%s\n' \
		'Architect app launcher targets:' \
		'  make apps                              Rebuild local Stable/Scratch app bundles' \
		'  make stable                            Launch a new Stable session' \
		'  make stable SESSION=HappyOtter         Restore a Stable session' \
		'  make scratch                           Launch a new Scratch session' \
		'  make scratch SESSION=BoldBadger        Restore a Scratch session' \
		'  make stable-new                        Launch a new Stable session' \
		'  make stable-restore SESSION=HappyOtter Restore a Stable session' \
		'  make scratch-new                       Launch a new Scratch session' \
		'  make scratch-restore SESSION=BoldBadger Restore a Scratch session' \
		'  make sessions                          List saved named sessions'

apps:
	. ./scripts/setup-macos-sdk-workaround.sh >/tmp/architect-sdk-workaround.log && $(ZIG) build -Doptimize=ReleaseFast
	$(BUNDLE_SCRIPT) "$(ARCHITECT_BIN)" "$(APP_DIR)" --app-name "Architect (Stable)"
	$(BUNDLE_SCRIPT) "$(ARCHITECT_BIN)" "$(APP_DIR)" --app-name "Architect (Scratch)"

stable: check-stable-app
	@if [ -n "$(SESSION)" ]; then \
		printf 'Restoring Stable session: %s\n' "$(SESSION)"; \
		$(OPEN) -n "$(STABLE_APP)" --args --session "$(SESSION)"; \
	else \
		printf 'Launching new Stable session\n'; \
		$(OPEN) -n "$(STABLE_APP)"; \
	fi

scratch: check-scratch-app
	@if [ -n "$(SESSION)" ]; then \
		printf 'Restoring Scratch session: %s\n' "$(SESSION)"; \
		$(OPEN) -n "$(SCRATCH_APP)" --args --session "$(SESSION)"; \
	else \
		printf 'Launching new Scratch session\n'; \
		$(OPEN) -n "$(SCRATCH_APP)"; \
	fi

stable-new: check-stable-app
	$(OPEN) -n "$(STABLE_APP)"

scratch-new: check-scratch-app
	$(OPEN) -n "$(SCRATCH_APP)"

stable-restore: require-session check-stable-app
	$(OPEN) -n "$(STABLE_APP)" --args --session "$(SESSION)"

scratch-restore: require-session check-scratch-app
	$(OPEN) -n "$(SCRATCH_APP)" --args --session "$(SESSION)"

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

require-session:
	@if [ -z "$(SESSION)" ]; then \
		printf 'SESSION is required. Example: make stable-restore SESSION=HappyOtter\n' >&2; \
		exit 1; \
	fi

check-stable-app:
	@if [ ! -d "$(STABLE_APP)" ]; then \
		printf 'Missing app bundle: %s\n' "$(STABLE_APP)" >&2; \
		printf 'Build local app bundles with: make apps\n' >&2; \
		exit 1; \
	fi

check-scratch-app:
	@if [ ! -d "$(SCRATCH_APP)" ]; then \
		printf 'Missing app bundle: %s\n' "$(SCRATCH_APP)" >&2; \
		printf 'Build local app bundles with: make apps\n' >&2; \
		exit 1; \
	fi
