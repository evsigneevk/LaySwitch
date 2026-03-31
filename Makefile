APP          = LaySwitch
INSTALL_DIR  = /Applications
BUNDLE_ID    = com.layswitch.app

.PHONY: build install uninstall logs

build:
	bash build.sh

install:
	@if [ ! -f "$(APP).app/Contents/MacOS/$(APP)" ]; then \
		echo "→ No built app found, building..."; \
		bash build.sh; \
	fi
	@if pgrep -x "$(APP)" > /dev/null; then \
		echo "→ Stopping running $(APP)..."; \
		pkill -x "$(APP)"; \
		sleep 0.5; \
	fi
	@echo "→ Installing $(APP).app to $(INSTALL_DIR)..."
	cp -r "$(APP).app" "$(INSTALL_DIR)/"
	@echo "→ Launching $(APP)..."
	open "$(INSTALL_DIR)/$(APP).app"

uninstall:
	@if pgrep -x "$(APP)" > /dev/null; then \
		echo "→ Stopping $(APP)..."; \
		pkill -x "$(APP)"; \
		sleep 0.5; \
	fi
	@if launchctl list "$(BUNDLE_ID)" > /dev/null 2>&1; then \
		echo "→ Removing from login items..."; \
		launchctl bootout "gui/$$(id -u)/$(BUNDLE_ID)" 2>/dev/null || true; \
	fi
	@rm -f "$$HOME/Library/LaunchAgents/$(BUNDLE_ID).plist"
	@if [ -d "$(INSTALL_DIR)/$(APP).app" ]; then \
		echo "→ Removing $(INSTALL_DIR)/$(APP).app..."; \
		rm -rf "$(INSTALL_DIR)/$(APP).app"; \
	fi
	@if [ -d "$$HOME/Library/Application Support/$(APP)" ]; then \
		echo "→ Removing saved layouts..."; \
		rm -rf "$$HOME/Library/Application Support/$(APP)"; \
	fi
	@echo "✓ $(APP) uninstalled"

logs:
	log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level info
