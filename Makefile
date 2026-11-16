# Melete. Needs full Xcode (SwiftData macros are not in Command Line Tools).
.PHONY: check build test app run debug-run clean

check:
	@xcode-select -p | grep -q "Xcode" || { echo "Melete needs full Xcode. Run: sudo xcode-select -s /Applications/Xcode.app"; exit 1; }

build: check
	swift build

test: check
	swift test

app: check
	scripts/bundle.sh release

# Debug build as an app (DEBUG features such as MELETE_DEBUG_STATE work).
debug-app: check
	scripts/bundle.sh debug

run: app
	-pkill -x Melete; open build/Melete.app

# Example: make debug-run STATE=paused
debug-run: debug-app
	-pkill -x Melete; MELETE_DEBUG_STATE=$(STATE) build/Melete.app/Contents/MacOS/Melete

clean:
	rm -rf .build build
