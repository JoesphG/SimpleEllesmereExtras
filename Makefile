.PHONY: all check lint format test package

all: check test

check: lint
	stylua --check .

lint:
	luacheck .

format:
	stylua .

# frames.lua is a stub library the panel suite loads, not a suite of its own.
test:
	for t in tests/*.lua; do \
		case "$$t" in tests/frames.lua) continue;; esac; \
		lua5.1 $$t || exit 1; \
	done

# Build the CurseForge zip locally without uploading anything.
package:
	curl -sL https://raw.githubusercontent.com/BigWigsMods/packager/v2.5.1/release.sh -o /tmp/simpleellesmereextras-release.sh
	chmod +x /tmp/simpleellesmereextras-release.sh
	/tmp/simpleellesmereextras-release.sh -d -t .
